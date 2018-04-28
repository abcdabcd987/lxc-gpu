# export APT_SOURCE='ftp.sjtu.edu.cn'
# export NVIDIA_DRIVER_INSTALLER='./NVIDIA-Linux-x86_64-390.48.run'


# Allow current user to create unprivileged containers
# See https://linuxcontainers.org/lxc/getting-started/
echo "$USER veth lxcbr0 10" | sudo tee -a /etc/lxc/lxc-usernet
mkdir -p ~/.config/lxc
export SUBUID=$(cat /etc/subuid | grep "$USER:" | awk -F : '{print $2 " " $3}')
export SUBGID=$(cat /etc/subgid | grep "$USER:" | awk -F : '{print $2 " " $3}')
cat > ~/.config/lxc/default.conf <<EOM
lxc.include = /etc/lxc/default.conf
lxc.id_map = u 0 $SUBUID
lxc.id_map = g 0 $SUBGID
EOM

# Download the lxc template
lxc-create -t download -n template -- \
    --server mirrors.tuna.tsinghua.edu.cn/lxc-images \
    --dist ubuntu --release xenial --arch amd64

# Copy the NVIDIA driver installer
sudo cp "$NVIDIA_DRIVER_INSTALLER" ~/.local/share/lxc/template/rootfs/nvidia-driver-installer.run
sudo chown --reference ~/.local/share/lxc/template/rootfs/bin/bash ~/.local/share/lxc/template/rootfs/nvidia-driver-installer.run

# Mount `/dev/nvidia*`
for x in $(ls /dev/nvidia*); do
    echo lxc.mount.entry = $x $(echo $x | cut -b 2-) none bind,optional,create=file >> ~/.local/share/lxc/template/config
done

# Start the container
chmod a+x ~/.local
lxc-start -n template -d

# `sudo` without password
lxc-attach -n template -- chmod +w /etc/sudoers
lxc-attach -n template -- sed -i 's/%sudo.*/%sudo ALL=(ALL:ALL) NOPASSWD:ALL/g' /etc/sudoers
lxc-attach -n template -- chmod -w /etc/sudoers

# Change apt source.
lxc-attach -n template -- sed -i "s|http://.*/ubuntu|http://$APT_SOURCE/ubuntu|g" /etc/apt/sources.list

# Update apt package list
lxc-attach -n template -- apt-get update

# Install essential packages
lxc-attach -n template -- apt-get install -y openssh-server tmux htop

# Install NVIDIA Drivers
lxc-attach -n template -- sh /nvidia-driver-installer.run --no-kernel-module  --silent

# Check `nvidia-smi`
lxc-attach -n template -- nvidia-smi

# Clean up
lxc-attach -n template -- apt-get clean
sudo rm ~/.local/share/lxc/template/rootfs/nvidia-driver-installer.run

# Stop the container
lxc-stop -n template

# Save the rootfs
sudo tar --numeric-owner -C ~/.local/share/lxc/template/ -czpf template.tar.gz rootfs
