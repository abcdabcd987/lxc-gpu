#!/usr/bin/env python3
import threading
import ldap
import os
import sqlite3
import threading
import queue
import atexit
import subprocess
import multiprocessing
import json
from datetime import datetime
from io import StringIO
from flask import Flask, request, redirect, url_for, flash, render_template, abort, Response, g, make_response
from pprint import pprint
from gevent.wsgi import WSGIServer
import settings

copy_queue = queue.Queue()
copy_log = []

def copy(args):
    host, text = args
    cmd = ['ssh', '-i', settings.IDENTITY_FILE, '-o', 'StrictHostKeyChecking no', 'iam@' + host]
    process = subprocess.Popen(cmd, universal_newlines=True, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out, err = process.communicate(text, timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        out, err = process.communicate()
    return host, out, err

def now():
    return '[' + datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f') + ']'

def thread_copy_ssh_key():
    global copy_log
    print('thread_copy_ssh_key started')
    conn = sqlite3.connect(settings.DB_NAME)
    conn.row_factory = sqlite3.Row
    while True:
        initiator = copy_queue.get()
        print('thread_copy_ssh_key: got task', initiator)
        if initiator == 'EXIT':
            return
        copy_log = [now() + 'task started by ' + str(initiator)]
        cur = conn.cursor()
        cur.execute('SELECT username, keys FROM keys')
        keys = {row['username']: row['keys'] for row in cur.fetchall()}
        users = list(keys.keys()) if initiator is None else [initiator]

        for username in keys:
            name = ldap_get_display_name(username)
            cur.execute('UPDATE users SET name=? WHERE username=?', (name, username))

        conn.commit()
        cur.close()

        msg = dict(user_keys=keys, users=users)
        text = json.dumps(msg, indent=2)
        tasks = [(s, text) for s in settings.SERVERS.values()]

        pool = multiprocessing.Pool(processes=max(len(settings.SERVERS), 1))
        for host, out, err in pool.imap(copy, tasks):
            copy_log.append(now() + host)
            out_lines = out.splitlines()
            out_lines = out_lines[out_lines.index('====== START IAM SHELL ======')+1:]
            copy_log.extend(out_lines)
            copy_log.append('-'*30)
        pool.terminate()
        pool.join()
        copy_log.append(now() + 'done')

app = Flask(__name__)

def get_db():
    db = getattr(g, '_database', None)
    if db is None:
        conn = sqlite3.connect(settings.DB_NAME)
        conn.executescript('''
        CREATE TABLE IF NOT EXISTS users (
            username TEXT UNIQUE,
            name TEXT,
            port INTEGER,
            subuid INTEGER
        );
        CREATE TABLE IF NOT EXISTS keys (
            username TEXT UNIQUE,
            keys TEXT
        );
        ''')
        conn.row_factory = sqlite3.Row
        db = g._database = conn
    return db

@app.teardown_appcontext
def close_connection(exception):
    db = getattr(g, '_database', None)
    if db is not None:
        db.close()

def ldap_get_display_name(username):
    ldap_url = 'ldap://{}/{}'.format(settings.LDAP_HOST, settings.LDAP_DOMAIN)
    l = ldap.initialize(ldap_url)
    l.simple_bind_s(settings.LDAP_IAM_USER, settings.LDAP_IAM_PASS)
    base = ','.join(['cn=users'] + settings.LDAP_BASE)
    res = l.search_s(base, ldap.SCOPE_SUBTREE, 'sAMAccountName=' + username, ['displayName'])
    name = ''
    if res:
        cn, d = res[0]
        names = d.get('displayName', [])
        name = names[0] if names else ''
    return str(name, 'utf-8')

def ldap_username_check(username):
    ldap_url = 'ldap://{}/{}'.format(settings.LDAP_HOST, settings.LDAP_DOMAIN)
    l = ldap.initialize(ldap_url)
    l.simple_bind_s(settings.LDAP_IAM_USER, settings.LDAP_IAM_PASS)
    base = ','.join(['cn=users'] + settings.LDAP_BASE)
    u = l.search_s(base, ldap.SCOPE_SUBTREE, 'sAMAccountName=' + username, ['sAMAccountName'])
    return len(u) > 0

def ldap_login_check(username, password):
    ldap_url = 'ldap://{}/{}'.format(settings.LDAP_HOST, settings.LDAP_DOMAIN)
    l = ldap.initialize(ldap_url)
    try:
        l.simple_bind_s(username + '@' + settings.LDAP_DOMAIN, password)
        return True
    except:
        return False

def get_user(username):
    cur = get_db().cursor()
    cur.execute('SELECT name, port, subuid FROM users WHERE username=?', (username, ))
    row = cur.fetchone()
    if row:
        return row['name'], row['port'], row['subuid']
    return None, None, None

def ensure_user(username):
    name, port, subuid = get_user(username)
    if not port:
        cur = get_db().cursor()
        cur.execute('SELECT MAX(port) AS max_port, MAX(subuid) AS max_subuid FROM users')
        row = cur.fetchone()
        port = max(settings.MIN_PORT, row['max_port']) + 1
        subuid = max(settings.MIN_SUBUID, row['max_subuid']) + 65536
        name = ldap_get_display_name(username)
        cur.execute('INSERT INTO users (username, name, port, subuid) VALUES (?, ?, ?, ?)', (username, name, port, subuid))
        get_db().commit()
    return name, port, subuid

@app.route('/user/<username>/name')
def get_name(username):
    name, port, subuid = get_user(username)
    if port:
        response = make_response(str(name))
        response.headers["content-type"] = "text/plain"
        return response
    else:
        abort(404)

@app.route('/user/<username>/port')
def get_port(username):
    name, port, subuid = get_user(username)
    if port:
        response = make_response(str(port))
        response.headers["content-type"] = "text/plain"
        return response
    else:
        abort(404)

@app.route('/user/<username>/subuid')
def get_subuid(username):
    name, port, subuid = get_user(username)
    if port:
        response = make_response(str(subuid))
        response.headers["content-type"] = "text/plain"
        return response
    else:
        abort(404)

@app.route('/user/<username>/.ssh/authorized_keys')
def get_ssh_key(username):
    name, port, subuid = get_user(username)
    if port:
        cur = get_db().cursor()
        cur.execute('SELECT keys FROM keys WHERE username=?', (username,))
        row = cur.fetchone()
        keys = row['keys'] if row else ''
        response = make_response(keys)
        response.headers["content-type"] = "text/plain"
        return response
    else:
        abort(404)

@app.route('/user/<username>/.ssh/config')
def get_ssh_config(username):
    sio = StringIO()
    for name, host in settings.SERVERS.items():
        sio.write('Host {}-manage\n'.format(name))
        sio.write('    HostName {}\n'.format(host))
        sio.write('    User {}\n'.format(username))
    cur = get_db().cursor()
    cur.execute('SELECT port FROM users WHERE username=?', (username,))
    row = cur.fetchone()
    if row:
        for name, host in settings.SERVERS.items():
            sio.write('Host {}\n'.format(name))
            sio.write('    HostName {}\n'.format(host))
            sio.write('    User {}\n'.format(username))
            sio.write('    Port {}\n'.format(row['port']))
    response = make_response(sio.getvalue())
    response.headers["content-type"] = "text/plain"
    return response


@app.route('/users')
def get_users_list():
    sio = StringIO()
    cur = get_db().cursor()
    cur.execute('SELECT * FROM users')
    users = cur.fetchall()
    for u in users:
        sio.write('{},{},{},{}\n'.format(u['username'], u['name'], u['port'], u['subuid']))
    response = make_response(sio.getvalue())
    response.headers["content-type"] = "text/plain"
    return response

@app.route('/manage/ssh-key', methods=['POST'])
def get_manage_ssh_key_redirect():
    username = request.form['username']
    return redirect(url_for('get_manage_ssh_key', username=username))

@app.route('/manage/ssh-key/<username>')
def get_manage_ssh_key(username):
    if ldap_username_check(username):
        ensure_user(username)
    else:
        abort(404)
    cur = get_db().cursor()
    cur.execute('SELECT keys FROM keys WHERE username=?', (username,))
    row = cur.fetchone()
    keys = row['keys'] if row else ''
    return render_template('manage_ssh_key.html', username=username, keys=keys)

@app.route('/manage/ssh-key/<username>', methods=['POST'])
def post_manage_ssh_key(username):
    password = request.form['password']
    keys = request.form['keys']
    if not ldap_login_check(username, password):
        abort(401)
    cur = get_db().cursor()
    cur.execute('DELETE FROM keys WHERE username=?', (username,))
    cur.execute('INSERT INTO keys (username, keys) VALUES (?, ?)', (username, keys))
    get_db().commit()
    copy_queue.put(username)
    return redirect(url_for('get_copy_ssh_key_log'))

@app.route('/manage/send-all-keys', methods=['POST'])
def post_send_all_keys():
    username = request.form['username']
    password = request.form['password']
    if not ldap_login_check(username, password):
        abort(401)
    copy_queue.put(None)
    return redirect(url_for('get_copy_ssh_key_log'))

@app.route('/log/push-keys')
def get_copy_ssh_key_log():
    text = '\n'.join(copy_log) + '\n'
    response = make_response(text)
    response.headers["content-type"] = "text/plain"
    if text.strip() and 'done' not in text:
        response.headers["Refresh"] = '1; url=' + url_for('get_copy_ssh_key_log')
    return response

@app.route('/')
def get_homepage():
    cur = get_db().cursor()
    cur.execute('SELECT * FROM users')
    users = cur.fetchall()
    return render_template('homepage.html', users=users)


if __name__ == '__main__':
    thread = threading.Thread(target=thread_copy_ssh_key)
    thread.daemon = True
    thread.start()
    def stop_thread():
        print('stopping thread')
        copy_queue.put('EXIT')
        thread.join()
        print('thread stopped')
    atexit.register(stop_thread)

    http_server = WSGIServer(('', settings.WEB_PORT), app)
    try:
        print('WSGIServer start')
        http_server.serve_forever()
    except KeyboardInterrupt:
        print('WSGIServer stopped')
