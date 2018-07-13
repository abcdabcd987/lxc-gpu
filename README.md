# lxc-gpu


## How it works

Let's assume:

* `gpu17` is the server name
* `172.16.2.17` is the server IP
* `lqchen` is the username
* `22031` is the port number for the user
* `http://iam.mylab.com` is the URL to IAM
* `ldap://ldap.mylab.com/mylab.com` is the LDAP or Active Directory

### Start the Container

1. User: `ssh gpu17-manage` with the SSH key
    * Alias to `ssh lqchen@172.16.2.17` based on `~/.ssh/config`
2. Server: `sshd` validates the SSH key in `/home/lqchen/.ssh/authorized_keys`
3. Server: `do_start()` in the custom shell `/public/login.bash`
4. Server: `curl http://iam.mylab.com/user/lqchen/port` to know that the port number for the user `lqchen` is `22031`
4. Server: `lxc-start` and wait until the container is up
5. Server: Check if the NVIDIA driver inside the container matches the host's
    * If not, install the same version of the driver inside the container
6. Server: `lxc-info` to know that the IP of the container is `10.0.3.160`
7. Server: `iptables` map `172.16.2.17:22031` to `10.0.3.160:22`

### Login the Container

1. User: `ssh gpu17` with the SSH key
    * Alias to `ssh lqchen@172.16.2.17 -p 22031` based on `~/.ssh/config`
2. Server: forward `172.16.2.17:22031` to `10.0.3.160:22`
3. Container: `sshd` validates the SSH key in `/home/lqchen/.ssh/authorized_keys`
4. Container: run user shell, e.g., `bash`

### Read Configurations on IAM

It's a really simple and straightforward procedure. IAM reads from its database and return the corresponding result.

### Write SSH Public Key to IAM

1. User: copy `~/.ssh/id_rsa.pub` and paste on `http://iam.mylab.com/manage/ssh-key/lqchen`
2. User: enter the LDAP password of the user and hit the save button
3. IAM: `post_manage_ssh_key()` in `iam.py` starts to handle the request
4. IAM: ask `ldap://ldap.mylab.com/mylab.com` if the username and the password matches
5. IAM: save the pair of the username and the SSH public key to IAM database
6. IAM: ask the IAM background worker to update SSH keys on servers

### IAM Updates SSH Keys

1. IAM: ask the IAM background worker to update SSH keys on servers
2. Worker: `thread_copy_ssh_key()` in `iam.py` wakes up
3. Worker: query the full name of all users on `ldap://ldap.mylab.com/mylab.com` with *the LDAP account for IAM* and update IAM database
4. Worker: read all users' SSH public keys from IAM database and encode them as a JSON string
5. Worker: `ssh iam@172.16.2.xxx` with *the IAM SSH key* to each server and send the JSON encoded string
6. Server: `sshd` validates the SSH key in `/home/iam/.ssh/authorized_keys`
7. Server: run the custom shell `/home/iam/iam-shell.bash` as `iam`
8. Server: run `/home/iam/set_authorized_keys.py` as `root`
9. Server: write SSH public keys to each user account
    * of the host: `/home/lqchen/.ssh/authorized_keys`
    * of the container: `/home/lqchen/.local/share/lxc/lqchen/rootfs/home/lqchen/.ssh/authorized_keys`
10: Server: merge all users' SSH public keys and write to the `register` account
    * `/home/register/.ssh/authorized_keys`

### Register a Container on a Sever

1. User: `ssh register@gpu17-manage lqchen` with the SSH key
    * Alias to `ssh register@172.16.2.17` based on `~/.ssh/config`
2. Server: `sshd` validates the SSH key in `/home/register/.ssh/authorized_keys`
3. Server: run the custom shell `/home/register/register.bash` as `register`
4. Server: run `/root/new-lxc.bash` as `root`
5. Server: `curl` IAM to know the user `lqchen`'s port number, `subuid`, `.ssh/authorized_keys`, and generated `.ssh/config`
6. Server: create user account `lqchen` on the host machine
    * add to the `sudo` group
    * set `subuid` and `subgid`
    * save `.ssh/authorized_keys`
    * grant LXC virtual network permission in `/etc/lxc/lxc-usernet`
7. Server: clone a container from the template
    * decompress the template container
    * fill the LXC configuration file: `subuid`, `subgid`, `rootfs`, hostname, NVIDIA device mount points
8. Server: `lxc-start` the container
9. Container: create user account `lqchen` inside the container
    * add to the `sudo` group
    * save `.ssh/authorized_keys` and `.ssh/config`
10. Server: `lxc-stop` the container
11. Server: set the default shell of user `lqchen` to the custom shell `/public/login.bash`


