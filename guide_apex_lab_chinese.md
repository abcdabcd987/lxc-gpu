## 概览

- 新用户在 [IAM](http://iam.apexlab.org/) 登记后自动获得 GPU Server 的权限，用户会在每台机器上分配到一个 LXC Container 以及一个在所有机器上相同的 SSH Port，之后用户可以自行在每台机器上完成初始化工作。
- LXC Container 可以简单理解成虚拟机，只不过实际上并没有做虚拟化，而是在 Linux 内核上做了隔离。
- 每个人对自己的 LXC Container 有完全的控制权限，对其他人的 LXC Container 没有感知。
- 物理机的资源（硬盘、内存、显卡）是所有 LXC Container 共用的。
- 在新分配的 LXC Container 中，预装好了 Ubuntu 16.04 LTS 64-bit 以及显卡驱动 381.09。
- 要使用固态硬盘以提高IO速度，请访问 `/SSD` 路径。
- 要使用NAS上的资源，请访问 `/newNAS` 路径。

## 在 IAM 上登记 SSH Key

用户在初次使用 GPU Server 之前，需要在 IAM 上登记信息。目前 IAM 绑定与域账号绑定，只需要提供额外的 SSH Key 信息。IAM 会分配给每个用户一个固定的 SSH Port，并且提供一些实用的功能。值得注意的是，在 IAM 上登记 SSH Key 之后，与 GPU Server 的所有 SSH 连接将不再需要输入密码。

首先打开 <http://iam.apexlab.org/>，在 *Manage SSH Authorized Keys* 下面输入你的域账户，点击 *Manage*。在新的页面中输入你的 SSH Key，每个一行，然后输入你的域账户密码，点击 *Apply*。如果一切正常，那么所有工作就完成了。

如果你没有 SSH Key，你可以在你的电脑上运行 `ssh-keygen` 来生成一个。如果你已经有了一个 SSH Key，你可以在电脑上运行 `cat ~/.ssh/id_rsa.pub` 来显示它，然后复制粘贴到 IAM 中。

IAM 提供了一个实用的工具，回到 [IAM首页](http://iam.apexlab.org/)，点击你的帐户对应的 *(.ssh/config)*，把它复制粘贴到你电脑的 `~/.ssh/config` 里面。之后，你就可以使用类似 `ssh gpu7-manage` 以及 `ssh gpu7` 这样的方式来访问 GPU Server，而不需要输入一长串的用户名、IP、端口。

## 初始化 LXC Container

如果你此前从未在某台 GPU Server 上运行过 LXC Container，你需要在这台机器上先执行初始化步骤。你需要以 `register` 用户连接该机器，并且把你的用户名附带上去。

```bash
ssh register@gpuN-manage username
```

![](http://apex.sjtu.edu.cn/public/files/guides/20170518/QQ20170518-221443@2x.png)

## 启动 LXC Container

```bash
ssh gpuN-manage
```

如果你的 LXC Container 没有启动，执行这个命令之后会被开启。如果已经启动，则会显示状态。

![](http://apex.sjtu.edu.cn/public/files/guides/20170518/QQ20170518-215738@2x.png)

## 进入 LXC Container

```bash
ssh gpuN
```

![](http://apex.sjtu.edu.cn/public/files/guides/20170518/QQ20170518-215756@2x.png)

## 关闭 LXC Container

你可以通过下面命令手动关闭你的 LXC Container：

```bash
ssh gpuN-manage stop
```

![](http://apex.sjtu.edu.cn/public/files/guides/20170518/QQ20170518-215843@2x.png)



## 备份 LXC Container

你可以把 LXC Container 备份到 NAS 上。首先你需要停止你的 LXC Container，然后根据提示执行操作。

```bash
ssh gpuN-manage stop
ssh gpuN-manage snapshot
ssh gpuN-manage snapshot token
```

![](http://apex.sjtu.edu.cn/public/files/guides/20170518/QQ20170518-220339@2x.png)

## 恢复 LXC Container

你可以从 NAS 上恢复之前备份的 LXC Container。首先你需要停止 LXC Container，然后根据提示执行操作。值得注意的是，你当前 LXC Container 的所有文件都会被删除。

```bash
ssh gpuN-manage stop
ssh gpuN-manage recover
ssh gpuN-manage recover token path/to/snapshot
```

![](http://apex.sjtu.edu.cn/public/files/guides/20170518/QQ20170518-220454@2x.png)

## 重做 LXC Container

如果你把 LXC Container 里面的系统搞崩了，想要重做系统也是可以的。这相当于从一个管理员预制的镜像中恢复。

```bash
ssh gpuN-manage stop
ssh gpuN-manage rebuild
ssh gpuN-manage recover token path/to/snapshot
```

![](http://apex.sjtu.edu.cn/public/files/guides/20170518/QQ20170518-220759@2x.png)

## 安装 Cuda 9.0

```bash
sudo apt update
sudo apt install -y build-essential
sudo sh /newNAS/Share/GPU_Server/cuda_9.0.176_384.81_linux.run --silent --toolkit
echo 'export PATH=$PATH:/usr/local/cuda/bin' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64' >> ~/.bashrc
. ~/.bashrc
```

## 安装 CuDNN 7.0

```bash
tar xf /newNAS/Share/GPU_Server/cudnn-9.0-linux-x64-v7.tgz -C /tmp
sudo cp -r /tmp/cuda/* /usr/local/cuda-9.0/
```

## 安装 TensorFlow

```bash
# for python 2.7
sudo apt install -y python-pip python-dev
sudo -H pip install tensorflow-gpu

# for python 3.6
sudo apt install -y python3-pip python3-dev
sudo -H pip3 install tensorflow-gpu
```
* 注意，请根据 [TensorFlow官网](https://www.tensorflow.org/install/install_sources)选择可以和之前安装的Cuda与CuDNN兼容的TensorFlow版本。


## 验证 TensorFlow 安装成功

```bash
python -c "import tensorflow as tf; tf.Session();"
```

如果出现了如下字样说明 TensorFlow 安装成功，并且可以正常使用GPU。

```
I tensorflow/core/common_runtime/gpu/gpu_device.cc:885] Found device 0 with properties:
name: GeForce GTX TITAN X
major: 5 minor: 2 memoryClockRate (GHz) 1.076
pciBusID 0000:02:00.0
Total memory: 11.95GiB
Free memory: 11.49GiB
I tensorflow/core/common_runtime/gpu/gpu_device.cc:906] DMA: 0
I tensorflow/core/common_runtime/gpu/gpu_device.cc:916] 0:   Y
I tensorflow/core/common_runtime/gpu/gpu_device.cc:975] Creating TensorFlow device (/gpu:0) -> (device: 0, name: GeForce GTX TITAN X, pci bus id: 0000:02:00.0)
<tensorflow.python.client.session.Session object at 0x7f544bbcafd0>
```

## 避免 TensorFlow 占满显存

TensorFlow 默认会占满所有的显存，而 GPU 属于共享资源。为了方便大家共用 GPU Server，请使用如下代码创建 `tf.Session`，将 TensorFlow 设置成显存按需增长模式：

```python
config = tf.ConfigProto(allow_soft_placement=True, log_device_placement=False)
config.gpu_options.allow_growth=True
sess = tf.Session(config=config)
```

## 嫌输入 `ssh user@gpu-server-ip -p port` 太麻烦？

IAM 提供了一个实用的工具，回到 [IAM首页](http://iam.apexlab.org/)，点击你的帐户对应的 *(.ssh/config)*，把它复制粘贴到你电脑的 `~/.ssh/config` 里面。之后，你就可以使用类似 `ssh gpu7-manage` 以及 `ssh gpu7` 这样的方式来访问 GPU Server，而不需要输入一长串的用户名、IP、端口。

广告：更多 SSH 基本用法（比如端口转发、图形界面转发等）详见 <https://zhuanlan.zhihu.com/p/21999778>


## FAQ

### 我可以在 LXC 容器里面跑 Jupyter Notebook / TensorBoard / 各种网页服务 吗？

可以，这是推荐用法。思路就是在远程跑，然后将端口转发到本地。比方说在 LXC 容器的 6006 端口开了一个 TensorBoard，现在要把它映射到本地的 16006 端口：

```bash
ssh -L16006:localhost:6006 user@ip -p port
```

然后就可以在本地的浏览器访问 `http://localhost:16006` 来访问 LXC 容器中的 TensorBoard 了。

### 文件要在本地和远程传来传去好麻烦 / 我想看远程跑的结果文件怎么办 / 我想要编辑远程的文件有没有什么方便的办法？

我的推荐做法是用 sshfs 将远程的文件系统挂载到本地，之后再用本地的文本编辑器 / 文件管理器 / ... 打开。

首先在本地创建一个用于挂载的空目录，比如说放在 `~/mnt/`，然后使用下面命令挂载/取消挂载远程的文件系统：

```bash
# for ubuntu:
sudo apt install sshfs  # install sshfs
sshfs -o idmap=user -p lxcport lxcuser@lxcip: ~/mnt  # mount remote filesystem
fusermount -u ~/mnt  # unmount

# for macOS
# see https://github.com/osxfuse/osxfuse/wiki/SSHFS for sshfs installation guide
sshfs -p lxcport lxcuser@lxcip: ~/mnt -o auto_cache,volname=gpu5-lxc  # mount remote filesystem
umount -f ~/mnt  # unmount
```

### 我的程序有 GUI 我想看一眼怎么办？

首先要在自己电脑上安装 X11 Server

* Windows 用户可以使用 [XMing](http://www.straightrunning.com/XmingNotes/)
* Mac 用户需要安装 [XQuartz](https://www.xquartz.org/)
* Linux 用户如有图形界面则无需特别设置

然后使用 `ssh -X` 来访问容器，在容器内安装 `xorg` 之后就可以将远程的 GUI 放在本地显示了。

```bash
local$ ssh -X lxcuser@lxcip -p lxcport
lxc-container$ sudo apt install xorg  # if not installed
lxc-container$ xeyes  # for example
lxc-container$ xeyes &  # or you can run in backround
```

![](http://apex.sjtu.edu.cn/public/files/guides/20170321/ssh-x.jpeg)
