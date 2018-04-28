#!/usr/bin/env python3
import json
import os
import sys

def write_ssh_keys(prompt, path, keys):
    sys.stdout.write('[{} '.format(prompt))
    abspath = os.path.abspath(path)
    if abspath != path:
        sys.stdout.write('malicious path: {}'.format(path))
        return
    try:
        with open(path, 'w') as f:
            f.write(keys)
        sys.stdout.write(' OK ')
    except:
        sys.stdout.write('FAIL')
    sys.stdout.write(']\t')


def main():
    if os.getuid() != 0:
        sys.stderr.write('Must run as root!\n')
        sys.exit(1)
    msg = json.loads(sys.stdin.read())
    keys_merged = []
    users = sorted(msg['users'])
    user_keys = msg['user_keys']
    for user in users:
        sys.stdout.write('{:<20}\t'.format(user))
        keys = user_keys[user]
        write_ssh_keys('user', '/home/{0}/.ssh/authorized_keys'.format(user), keys)
        write_ssh_keys('lxc', '/home/{0}/.local/share/lxc/{0}/rootfs/home/{0}/.ssh/authorized_keys'.format(user), keys)
        sys.stdout.write('\n')
        keys_merged.extend(keys.splitlines())
    keys_merged = '\n'.join(keys_merged) + '\n'
    sys.stdout.write('{:<20}\t'.format('register'))
    write_ssh_keys('merged', '/home/register/.ssh/authorized_keys', keys_merged)
    sys.stdout.write('\n')
    

if __name__ == '__main__':
    main()
