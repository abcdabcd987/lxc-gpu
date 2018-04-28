# export APT_SOURCE='ftp.sjtu.edu.cn'
# export SCRIPTS='/newNAS/Share/GPU_Server'
# export NVIDIA_DRIVER_INSTALLER="$SCRIPTS/NVIDIA-Linux-x86_64-390.48.run"
# export REGISTER_BASH="$SCRIPTS/register.bash"
# export LOGIN_BASH="$SCRIPTS/login.bash"
# export LXC_CONFIG_TEMPLATE="$SCRIPTS/lxc-config.template"
# export TEMPLATE_TAR_GZ="$SCRIPTS/template.tar.gz"
# export NEW_LXC_BASH="$SCRIPTS/new-lxc.bash"
# export DEL_USER_BASH="$SCRIPTS/del-user.bash"
# export IAM_ID_RSA_PUB="$SCRIPTS/iam_id_rsa.pub"
# export IAM_SHELL_BASH="$SCRIPTS/iam-shell.bash"
# export SET_AUTHORIZED_KEYS_PY="$SCRIPTS/set_authorized_keys.py"

# Allow `sudo` without password. Interactively, `sudo visudo`.
sudo chmod +w /etc/sudoers
sudo sed -i 's/%sudo.*/%sudo ALL=(ALL:ALL) NOPASSWD:ALL/g' /etc/sudoers
sudo chmod -w /etc/sudoers

# Change apt source. Interactively, `sudo vim /etc/apt/sources.list`.
sudo sed -i "s|http://.*/ubuntu|http://$APT_SOURCE/ubuntu|g" /etc/apt/sources.list

# Update apt package list
sudo apt-get update

# Setup NFS
sudo apt-get install -y nfs-common
sudo mkdir -p /NAS/{Dataset,Share,Workspaces}
sudo mkdir -p /newNAS/{Dataset,Share,Workspaces}
sudo mkdir -p /newNAS/Workspaces/{DMGroup,CVGroup,UCGroup,DRLGroup,AdsGroup,CrowdsourcingGroup,MLGroup,NLPGroup}
sudo mkdir -p /newNAS/Dataset/{DMGroup,CVGroup,UCGroup,DRLGroup,AdsGroup,CrowdsourcingGroup,MLGroup,NLPGroup}
sudo chmod -R 777 /NAS /newNAS
cat <<EOM | sudo tee -a /etc/fstab
172.16.2.30:/mnt/NAS/Dataset    /NAS/Dataset    nfs rw 0 0
172.16.2.30:/mnt/NAS/Workspaces /NAS/Workspaces nfs rw 0 0
172.16.2.30:/mnt/NAS/Share      /NAS/Share      nfs rw 0 0
172.16.2.40:/mnt/NAS/Workspaces/DMGroup            /newNAS/Workspaces/DMGroup            nfs rw 0 0
172.16.2.40:/mnt/NAS/Workspaces/CVGroup            /newNAS/Workspaces/CVGroup            nfs rw 0 0
172.16.2.40:/mnt/NAS/Workspaces/UCGroup            /newNAS/Workspaces/UCGroup            nfs rw 0 0
172.16.2.40:/mnt/NAS/Workspaces/MLGroup            /newNAS/Workspaces/MLGroup            nfs rw 0 0
172.16.2.40:/mnt/NAS/Workspaces/DRLGroup           /newNAS/Workspaces/DRLGroup           nfs rw 0 0
172.16.2.40:/mnt/NAS/Workspaces/AdsGroup           /newNAS/Workspaces/AdsGroup           nfs rw 0 0
172.16.2.40:/mnt/NAS/Workspaces/NLPGroup           /newNAS/Workspaces/NLPGroup           nfs rw 0 0
172.16.2.40:/mnt/NAS/Workspaces/CrowdsourcingGroup /newNAS/Workspaces/CrowdsourcingGroup nfs rw 0 0
172.16.2.40:/mnt/NAS/Datasets/DMGroup            /newNAS/Datasets/DMGroup            nfs rw 0 0
172.16.2.40:/mnt/NAS/Datasets/CVGroup            /newNAS/Datasets/CVGroup            nfs rw 0 0
172.16.2.40:/mnt/NAS/Datasets/UCGroup            /newNAS/Datasets/UCGroup            nfs rw 0 0
172.16.2.40:/mnt/NAS/Datasets/MLGroup            /newNAS/Datasets/MLGroup            nfs rw 0 0
172.16.2.40:/mnt/NAS/Datasets/DRLGroup           /newNAS/Datasets/DRLGroup           nfs rw 0 0
172.16.2.40:/mnt/NAS/Datasets/AdsGroup           /newNAS/Datasets/AdsGroup           nfs rw 0 0
172.16.2.40:/mnt/NAS/Datasets/NLPGroup           /newNAS/Datasets/NLPGroup           nfs rw 0 0
172.16.2.40:/mnt/NAS/Datasets/CrowdsourcingGroup /newNAS/Datasets/CrowdsourcingGroup nfs rw 0 0
EOM
sudo mount -a

# Install essential softwares
sudo apt-get install -y build-essential linux-headers-$(uname -r) htop tmux lxc ntp wget grep awk sed curl

# Install NVIDIA Drivers
sudo "$NVIDIA_DRIVER_INSTALLER" --silent

# Check nvidia-smi
nvidia-smi

# Fix `nvidia-uvm`
sudo wget -O /root/start-nvidia.bash https://raw.githubusercontent.com/abcdabcd987/lxc-gpu/master/start-nvidia.bash
cat <<EOM | sudo tee /etc/rc.local
#!/bin/sh -e
/root/start-nvidia.bash
exit 0
EOM
sudo chmod +x /etc/rc.local
sudo chmod +x /root/start-nvidia.bash
sudo /root/start-nvidia.bash

# Check /dev/nvidia*
ls /dev/nvidia*

# Copy lxc-gpu related files
sudo mkdir /public
sudo cp "$LOGIN_BASH" /public/login.bash
sudo cp "$REGISTER_BASH" /public/register.bash
sudo chmod +x /public/login.bash /public/register.bash
sudo cp "$NEW_LXC_BASH" /root/new-lxc.bash
sudo cp "$DEL_USER_BASH" /root/del-user.bash
sudo chmod +x /root/new-lxc.bash /root/del-user.bash
sudo mkdir /root/lxc-public-images
sudo cp "$TEMPLATE_TAR_GZ" /root/lxc-public-images/template.tar.gz
sudo cp "$LXC_CONFIG_TEMPLATE" /root/lxc-public-images/lxc-config.template

# Create `register` user
sudo useradd -m -Gsudo -s /public/register.bash register
sudo mkdir -p /home/register/.ssh
sudo touch /home/register/.ssh/authorized_keys
sudo chown -R register:register /home/register/.ssh
sudo chmod 700 /home/register/.ssh
sudo chmod 600 /home/register/.ssh/authorized_keys

# Create `iam` user
sudo useradd -m -Gsudo -s /home/iam/iam-shell.bash iam
sudo mkdir -p /home/iam/.ssh
sudo cp "$IAM_ID_RSA_PUB" /home/iam/.ssh/authorized_keys
sudo chmod 700 /home/iam/.ssh
sudo chmod 600 /home/iam/.ssh/authorized_keys
sudo cp "$IAM_SHELL_BASH" /home/iam/iam-shell.bash
sudo cp "$SET_AUTHORIZED_KEYS_PY" /home/iam/set_authorized_keys.py
sudo chmod +x /home/iam/iam-shell.bash /home/iam/set_authorized_keys.py
sudo chown -R iam:iam /home/iam
