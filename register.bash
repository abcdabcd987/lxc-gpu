#!/bin/bash
shift
set -e
sudo su -c "/root/new-lxc.bash $@"
