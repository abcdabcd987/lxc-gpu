#!/bin/bash

USERNAME=$1
if [[ -z "$USERNAME" ]]; then
    echo "Please give me a username"
    exit 1
fi
id -u $USERNAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "User $USERNAME already exist"
    exit 1
fi

printf "Allocating LXC Container for \e[96;1m$USERNAME\e[0m...\n"

# fetch user iam info
echo "Fetchting IAM information..."
IAM_HOST="iam.apexlab.org"
IAM_PORT=$(curl -s -f http://$IAM_HOST/user/$USERNAME/port)
if [ $? -ne 0 ]; then printf "Failed to get IAM information. Maybe visit \e[96;1;4mhttp://iam.apexlab.org/\e[0m\n"; exit 1; fi
IAM_SUBUID=$(curl -s -f http://$IAM_HOST/user/$USERNAME/subuid)
if [ $? -ne 0 ]; then printf "Failed to get IAM information. Maybe visit \e[96;1;4mhttp://iam.apexlab.org/\e[0m\n"; exit 1; fi
IAM_KEYS=$(curl -s -f http://$IAM_HOST/user/$USERNAME/.ssh/authorized_keys)
if [ $? -ne 0 ]; then printf "Failed to get IAM information. Maybe visit \e[96;1;4mhttp://iam.apexlab.org/\e[0m\n"; exit 1; fi
IAM_SSHCONFIG=$(curl -s -f http://$IAM_HOST/user/$USERNAME/.ssh/config)
if [ $? -ne 0 ]; then printf "Failed to get IAM information. Maybe visit \e[96;1;4mhttp://iam.apexlab.org/\e[0m\n"; exit 1; fi

unset XDG_SESSION_ID XDG_RUNTIME_DIR

# create user
echo "Creating user..."
useradd -m -G sudo -s /bin/bash $USERNAME # will change the shell later
sed "/$USERNAME:/d" -i /etc/subuid
sed "/$USERNAME:/d" -i /etc/subgid
echo "$USERNAME:$IAM_SUBUID:65536" >> /etc/subuid
echo "$USERNAME:$IAM_SUBUID:65536" >> /etc/subgid
mkdir /home/$USERNAME/.ssh
touch /home/$USERNAME/.ssh/authorized_keys
touch /home/$USERNAME/.ssh/config
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys
echo "$IAM_KEYS" > /home/$USERNAME/.ssh/authorized_keys

# grant lxc virtual network permission
echo "Granting LXC virtual network permission..."
echo $USERNAME veth lxcbr0 10 >> /etc/lxc/lxc-usernet

# clone and config the container
echo "Cloning the container..."
LXCROOT=/home/$USERNAME/.local/share/lxc/$USERNAME
MACADDR=$(tr -dc A-F0-9 < /dev/urandom | head -c 6 | sed -r 's/(..)/\1:/g;s/:$//;s/^/00:16:3e:/')
mkdir -p $LXCROOT
tar --same-owner -xf /root/lxc-public-images/template.tar.gz -C /home/$USERNAME/.local/share/lxc/$USERNAME
cp -r /root/lxc-public-images/lxc-config.template $LXCROOT/config
cat >> $LXCROOT/config <<-EOM
# lxc.network.hwaddr = $MACADDR

lxc.id_map = u 0 $IAM_SUBUID 65536
lxc.id_map = g 0 $IAM_SUBUID 65536
lxc.rootfs = $LXCROOT/rootfs
lxc.utsname = $USERNAME
EOM
for x in $(ls /dev/nvidia*); do
    echo lxc.mount.entry = $x $(echo $x | cut -b 2-) none bind,optional,create=file >> $LXCROOT/config
done
HOSTNAME=$(hostname)
echo "$HOSTNAME-$USERNAME" > $LXCROOT/rootfs/etc/hostname
sed -i "s/template/$HOSTNAME-$USERNAME/g" $LXCROOT/rootfs/etc/hosts

# fix filesystem permission
echo "Fixing filesystem permission..."
FILES_SUID=$(find $LXCROOT -perm -4000)
FILES_SGID=$(find $LXCROOT -perm -2000)
chown $USERNAME:$USERNAME /home/$USERNAME/.local
chown $USERNAME:$USERNAME /home/$USERNAME/.local/share
chown $USERNAME:$USERNAME /home/$USERNAME/.local/share/lxc
chown $USERNAME:$USERNAME /home/$USERNAME/.local/share/lxc/$USERNAME
chown $USERNAME:$USERNAME /home/$USERNAME/.local/share/lxc/$USERNAME/config
chown -R $IAM_SUBUID:$IAM_SUBUID $LXCROOT/rootfs
chmod a+x /home/$USERNAME/.local
chmod a+x /home/$USERNAME/.local/share
chmod a+x /home/$USERNAME/.local/share/lxc
chmod a+x /home/$USERNAME/.local/share/lxc/$USERNAME
chmod 7777 $LXCROOT/rootfs/tmp
while read -r line; do chmod u+s $line; done <<< "$FILES_SUID"
while read -r line; do chmod g+s $line; done <<< "$FILES_SGID"

# adduser in the container
echo "Adding user in the container..."
su -c "lxc-start -n $USERNAME -d" $USERNAME
su -c "lxc-attach -n $USERNAME -- useradd -m -G sudo -s /bin/bash $USERNAME" $USERNAME
su -c "lxc-attach -n $USERNAME -- mkdir /home/$USERNAME/.ssh" $USERNAME
su -c "lxc-attach -n $USERNAME -- touch /home/$USERNAME/.ssh/authorized_keys" $USERNAME
su -c "lxc-attach -n $USERNAME -- touch /home/$USERNAME/.ssh/config" $USERNAME
su -c "lxc-attach -n $USERNAME -- chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh" $USERNAME
su -c "lxc-attach -n $USERNAME -- chmod 700 /home/$USERNAME/.ssh" $USERNAME
su -c "lxc-attach -n $USERNAME -- chmod 600 /home/$USERNAME/.ssh/authorized_keys" $USERNAME
su -c "lxc-stop -n $USERNAME" $USERNAME
echo "$IAM_KEYS" > $LXCROOT/rootfs/home/$USERNAME/.ssh/authorized_keys
echo "$IAM_SSHCONFIG" > $LXCROOT/rootfs/home/$USERNAME/.ssh/config

# finish
usermod -s /public/login.bash $USERNAME
echo "Done!"
