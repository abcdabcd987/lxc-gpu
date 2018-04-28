#!/bin/bash

USERNAME=$1
if [[ -z "$USERNAME" ]]; then
    echo "Please give me a username"
    exit 1
fi

echo "This script will"
echo "1. Change the shell of $USERNAME to /bin/bash"
echo "2. Stop lxc container $USERNAME"
echo "3. rm /public/ports/$USERNAME"
echo "4. sed -i '/$USERNAME /d' /etc/lxc/lxc-usernet"
echo "5. userdel -f -r $USERNAME"
echo ""
read -p "Are you sure (y/n)? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    chsh -s /bin/bash $USERNAME
    su - $USERNAME -c "lxc-stop -n $USERNAME"
    rm /public/ports/$USERNAME
    sed -i '/$USERNAME /d' /etc/lxc/lxc-usernet
    userdel -f -r $USERNAME
    echo "Done!"
else
    echo "Canceled"
    exit 1
fi