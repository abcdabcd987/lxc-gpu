#!/usr/bin/env python3
import bisect
import os
import re
import requests
import time
import socket
import struct
import ipaddress
from natsort import natsorted
from datetime import datetime
from flask import Flask, request, redirect, url_for, render_template, abort, Response, g, make_response, jsonify
from gevent.wsgi import WSGIServer
import settings

class IAMUsers:
    def __init__(self):
        self._users = {}
        self._last_updated = 0

    def update(self):
        if time.time() - self._last_updated < 300:
            return
        r = requests.get(settings.IAM_URL + '/users')
        if r.status_code != 200:
            return
        users = {}
        for line in r.text.splitlines():
            username, name, port, subuid = line.split(',')
            users[username] = dict(name=name, subuid=int(subuid))
        sorted_by_subuid = sorted(users.items(), key=lambda r: r[1]['subuid'])
        bisect_keys = [r[1]['subuid'] for r in sorted_by_subuid]
        self._users = users
        self._sorted_by_subuid = sorted_by_subuid
        self._bisect_keys = bisect_keys
        self._last_updated = time.time()

    def get_name(self, username):
        if username in self._users:
            return self._users[username]['name']
        return None

    def find_username(self, subuid):
        idx = bisect.bisect_right(self._bisect_keys, subuid) - 1
        if 0 <= idx < len(self._sorted_by_subuid):
            return self._sorted_by_subuid[idx][0]


class Server:
    def __init__(self, iam):
        self._iam = iam
        self.last_updated = None
        self.mounts = {}
        self.users = {}
        self.io = {}
        self._gpu_processes = {}

    def _mark_updated(self):
        self.last_updated = time.time()

    def feed_mpstat(self, text):
        idle = None
        ncpus = -2
        for line in text.splitlines():
            if line.startswith('Average:'):
                ncpus += 1
                split = line.split()
                if split[1] == 'all':
                    idle = float(split[-1])
        if idle is not None:
            self.cpu_usage = int(100 - idle)
            self.cpu_cores = ncpus
            self._mark_updated()
            return True
        return False

    def feed_sensors(self, text):
        cpu_temp = []
        for line in text.splitlines():
            if line.startswith('Physical id '):
                matches = re.findall(r'Physical id \d+:(.*?)°C', line)
                if matches:
                    cpu_temp.append(float(matches[0]))
        if cpu_temp:
            self.cpu_temp = int(sum(cpu_temp) / len(cpu_temp))
            self._mark_updated()
            return True
        return False

    def feed_df(self, text):
        mounts = {}
        for line in text.splitlines()[1:]:
            dev, size, used, free, usage, mount = map(str.strip, line.split())
            dev = dev.replace('/dev/', '')
            if mount in ['/', '/home', '/SSD']:
                usage = int(usage[:-1])
                mounts[mount] = dict(dev=dev, size=size, used=used, free=free, usage=usage)
        if '/SSD' in mounts:
            del mounts['/']
        self.mounts = mounts
        self._mark_updated()
        return True

    def feed_iostat(self, text):
        io = {}
        lines = text.splitlines()
        header_line = next(i for i, line in enumerate(lines) if line.startswith('Device:'))
        for line in lines[header_line+1:]:
            if not line:
                continue
            dev, rrqms, wrqms, rs, ws, rkbs, wkbs, avgrqsz, avgqusz, await_, r_await, w_await, svctm, util = map(str.strip, line.split())
            for d in self.mounts.values():
                if dev in d['dev']:
                    io[dev] = dict(read=float(rkbs) / 1024., write=float(wkbs) / 1024., util=int(float(util)))
                    break
        self.io = io
        self._mark_updated()
        return True

    def feed_nvidia(self, text):
        VALUE_START = 38
        gpus = []
        processes = {}
        section = ''
        for line in text.splitlines():
            if len(line) < VALUE_START-2 or line[VALUE_START-2] != ':':
                section = line.strip()
            if line.startswith('GPU'):
                cur_gpu = {}
                gpus.append(cur_gpu)
            elif 'Product Name' in line:
                cur_gpu['name'] = line[VALUE_START:].strip()
            elif 'Total' in line and section == 'FB Memory Usage':
                cur_gpu['mem_total'] = int(line[VALUE_START:].replace('MiB', '')) / 1024.
            elif 'Used' in line and section == 'FB Memory Usage':
                cur_gpu['mem_used'] = int(line[VALUE_START:].replace('MiB', '')) / 1024.
            elif 'Free' in line and section == 'FB Memory Usage':
                cur_gpu['mem_free'] = int(line[VALUE_START:].replace('MiB', '')) / 1024.
            elif 'Gpu' in line and section == 'Utilization':
                cur_gpu['util'] = int(line[VALUE_START:].replace('%', ''))
            elif 'GPU Current Temp' in line:
                cur_gpu['temp'] = int(line[VALUE_START:].replace('C', ''))
            elif 'Process ID' in line:
                cur_pid = int(line[VALUE_START:])
            elif 'Used GPU Memory' in line:
                memory = int(line[VALUE_START:].replace('MiB', ''))
                processes[cur_pid] = processes.get(cur_pid, 0) + memory
        self.gpus = gpus
        self._gpu_processes = processes
        self._mark_updated()
        return True

    def feed_ps(self, text):
        users = {}
        for line in text.splitlines()[1:]:
            user, pid, cpu, mem, vsz, rss, tty, stat, start, time, cmd = map(str.strip, line.split(maxsplit=10))
            try:
                subuid = int(user)
            except ValueError:
                continue
            username = self._iam.find_username(subuid)
            if username is not None:
                if username not in users:
                    users[username] = dict(cpu=0., rss=0., gpu_mem=0.)
                u = users[username]
                u['cpu'] += float(cpu)
                u['rss'] += float(rss) / 1024. / 1024.
                u['gpu_mem'] += self._gpu_processes.get(int(pid), 0) / 1024.
        self.users = users
        self._mark_updated()
        return True

    def feed_free(self, text):
        mem_line = text.splitlines()[1]
        total, used, free, shared, buff, avail = map(int, mem_line.split()[1:])
        self.mem_used = used / 1024. / 1024.
        self.mem_total = total / 1024. / 1024.
        self.mem_free = (total - used) / 1024. / 1024.
        self._mark_updated()
        return True


def nbsp(x):
    return x.replace(' ', '&nbsp;')


app = Flask(__name__)
app.jinja_env.filters['nbsp'] = nbsp
app.jinja_env.globals.update(max=max)
iam = IAMUsers()
servers = {}
server_names = []


@app.route('/feed/<server>/<program>', methods=['POST'])
def post_feed(server, program):
    ip = request.environ.get('HTTP_X_FORWARDED_FOR')
    if ip is None:
        ip = request.environ['REMOTE_ADDR']
    ip = ipaddress.ip_address(ip)
    ipv4 = ip.ipv4_mapped if ip.version == 6 else None
    ok = False
    for subnet in settings.FEED_ALLOWED_IP:
        network = ipaddress.ip_network(subnet)
        if ip in network or (ipv4 is not None and ipv4 in network):
            ok = True
            break
    if not ok:
        abort(403)

    global server_names
    iam.update()
    if server not in servers:
        servers[server] = Server(iam)
        server_names = natsorted(servers.keys())
    s = servers[server]
    func = getattr(s, 'feed_' + program, None)
    status = 'invalid feed: {}'.format(program)
    if func is not None:
        ok = func(str(request.get_data(), 'utf-8'))
        status = 'ok' if ok else 'fail'
    return jsonify(dict(status=status))


@app.route('/')
def get_homepage():
    iam.update()
    last_updated = getattr(g, 'last_updated', 0)
    now = time.time()
    if now - last_updated > 3:
        g.last_updated = now
        warnings = []
        for server_name in server_names:
            server = servers[server_name]
            diff = now - server.last_updated
            if diff > 30:
                warnings.append("Server [{}] hasn't updated yet for more than {:.0f} seconds.".format(server_name, diff))
        g.rendered = render_template('homepage.html', servers=servers, server_names=server_names, iam=iam, warnings=warnings, remarks=settings.REMARKS)
    return g.rendered


if __name__ == '__main__':
    # app.run('0.0.0.0', port=settings.WEB_PORT, debug=True)
    http_server = WSGIServer(('', settings.WEB_PORT), app)
    try:
        print('WSGIServer start')
        http_server.serve_forever()
    except KeyboardInterrupt:
        print('WSGIServer stopped')
