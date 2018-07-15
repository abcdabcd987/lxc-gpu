# lxc-gpu

Enjoy computation resources sharing at your laboratory with `lxc-gpu`!

## How to use (for users)

**This section is for users, and the rest of this document is for sysadmins.** I'd recommend sysadmins to write a guide for your laboratory. If there is not, this section gives you a basic grasp of `lxc-gpu`.

`lxc-gpu` is designed to be password-less. When you login to servers, you use your SSH keys. Use `ssh-keygen` to generate one if you don't have yet. Put your SSH public key at the IAM (Ask your sysadmin for the URL), enter the password for your laboratory domain account (Ask your sysadmin), and click save. You can save the `.ssh/config` from the IAM so that you don't need to type each server's IP and port.

* The first time you login to a server, you need to register on the server. Run `ssh register@SERVERNAME-manage USERNAME`.
* To boot your container, run `ssh SERVERNAME-manage`.
* To login to your container, run `ssh SERVERNAME`.
* There are some other functions, see `ssh SERVERNAME-manage` for more detail, including
    * `ssh SERVERNAME-manage port`: Port forwarding
    * `ssh SERVERNAME-manage snapshot`: Take a snapshot
    * `ssh SERVERNAME-manage recover`: Recover from a snapshot
    * `ssh SERVERNAME-manage rebuild`: Recover from the template
    * `ssh SERVERNAME-manage stop`: Shutdown the container

Once you've logged in to your container, you can operate it just like a bare metal while sharing computation and storage resources with other users. Especially, you have the `root` privilege and the access to GPUs.

There is also a webpage that refreshes every few seconds to show you the load of each server. Ask your sysadmin for the URL.

Enjoy researching!

### How to use the IAM

[![YouTube: How to use the IAM](https://img.youtube.com/vi/Z-E7VeY4Q9s/0.jpg)](https://www.youtube.com/watch?v=Z-E7VeY4Q9s)

### How to login to the container

[![Asciinema: How to login the container](https://asciinema.org/a/191738.png)](https://asciinema.org/a/191738)

### Server Load Monitor

[![Server Load Monitor](https://i.imgur.com/J1aQ1cj.png)](https://i.imgur.com/J1aQ1cj.png)

------------------------------

**The rest of this document is for sysadmins.**

## Motivation

Back in the first days when I joined the [*APEX Data & Knowledge Management Lab*](http://apex.sjtu.edu.cn/) at [*Shanghai Jiao Tong University*](http://www.sjtu.edu.cn/) in 2016, I found researchers frequently distracted by software misconfigurations, especially when they were using shared GPU servers. The server administrator had to give `sudo` privileges to all researchers because lots of software are difficult to install without `apt-get`. However, most researchers don't have the skill set to properly set up the software environment (They don't have to!). Usually, they just copy and paste commands from the web (This is alright!), which might indeed suits the researcher's need but destroys all others'. For example, [*Caffee*](http://caffe.berkeleyvision.org/) and [*TensorFlow*](https://www.tensorflow.org/) might need different versions of CUDA.

Of course, those researchers who broke the system are not to blame, as I believe that researchers should focus on research itself thus only have to know basic system operation skills (like copy and paste commands from the web). I, as a sysadmin and a researcher, would like to create a system so that

* Users are isolated. Software misconfiguration won't affect other users.
* Computation resources are shared. Because the funding might not be rich enough :(
    * Especially, users should be able to share GPUs.
    * Also, easy access to SSD (for faster IO), HDD (for larger storage), and NAS (for network storage)
* Users should have the "`root` privilege" to install whatever they want.
* Users should not have any chance to accidentally jeopardize the functioning of this system, even though they have the "`root` privilege".
* Performance overhead should be extremely small.
* The system should have user-friendly interfaces to both researchers and sysadmins.

## What it is

`lxc-gpu` consists of series of shell scripts and simple utilities. All the hard work are carried by [`LXC`](https://linuxcontainers.org/lxc/introduction/). Our project is a template for sysadmins to provide user-friendly computation resources sharing system.

The project contains the following parts:

* `iam/`: Website for Identity & Access Management
* `monitor/`: Website for hardware resources monitoring
* `scripts/`: Scripts served as a more user-friendly interface
* `setup/`: Installation scripts

## Installation

Before installing `lxc-gpu`, make sure your laboratory has a [LDAP](https://en.wikipedia.org/wiki/Lightweight_Directory_Access_Protocol)-compatible directory service, such as [*OpenLDAP*](https://www.openldap.org/) and [*Active Directory*](https://en.wikipedia.org/wiki/Active_Directory), as **`lxc-gpu` authenticates users through the LDAP service**.

I also recommend your laboratory to have a [NAS](https://en.wikipedia.org/wiki/Network-attached_storage) server, such as [*FreeNAS*](http://www.freenas.org/). `lxc-gpu` does not have to rely on NAS, but without NAS, the installation could be more complicated (you need to copy scripts and NVIDIA driver to all machines) and some features could be less user-friendly (users need to ask the sysadmin to copy their snapshots of the container to the target machine).

Our laboratory has the following infrastructures, for you reference:

* Ubuntu Server x64 16.04 / 18.04
* FreeNAS
* Active Directory

Installation scripts locate at `setup/` directory. Although these scripts should be able to run successfully given correct configuration, **I recommend that you read them carefully, adapt them to fit the infrastructure of your laboratory, and finally execute them line by line instead of running in batch.** The scripts are designed for Ubuntu only. If you use other Linux distribution, especially non-deb package manager, you would need lots of modification to the scripts.

To install `lxc-gpu`:

1. Rename `env.example.sh` to `env.sh`
2. Edit environment variables in `env.sh`
3. Edit scripts in `scripts/` directory to fit the infrastructure of your laboratory
4. Copy related files to the corresponding path as specified in `env.sh`
5. Create the template LXC container by running `create-lxc-template.bash` **on an arbitrary machine**
6. Read `setup-gpu-server.bash` carefully, adapt it to fit the infrastructure of your laboratory, and finally execute it line by line instead of running in batch **on each computation server**
7. Install `iam/` and `monitor/` **on a web server**
    * Rename `settings.example.py` to `settings.py` and change the settings
    * `pip3 install -r requirements.txt`
    * Both *IAM* and *monitor* are [Flask](http://flask.pocoo.org/docs/1.0/) applications in Python 3. Refer to [Flask Deployment Options](http://flask.pocoo.org/docs/1.0/deploying/) for more detail.
8. **Write a guide for users.** For your reference, [here is the guide at the APEX Lab (Chinese only)](guide_apex_lab_chinese.md)

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
4. Server: `curl` IAM to know that the port number for the user `lqchen` is `22031`
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

It's a really simple and straightforward procedure. IAM reads from its database and returns the corresponding result.

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
5. Worker: `ssh iam@172.16.2.17` with *the IAM SSH key* to each server and send the JSON encoded string
6. Server: `sshd` validates the SSH key in `/home/iam/.ssh/authorized_keys`
7. Server: run the custom shell `/home/iam/iam-shell.bash` as `iam`
8. Server: run `/home/iam/set_authorized_keys.py` as `root`
9. Server: write SSH public keys to each user account
    * of the host: `/home/lqchen/.ssh/authorized_keys`
    * of the container: `/home/lqchen/.local/share/lxc/lqchen/rootfs/home/lqchen/.ssh/authorized_keys`
10. Server: merge all users' SSH public keys and write to the `register` account
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


