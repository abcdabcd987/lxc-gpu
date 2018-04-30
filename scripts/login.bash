#!/bin/bash
IAM_HOST="iam.apexlab.org"
SNAPSHOT_PATH="/NAS/Workspaces/lxc-snapshot"
NVIDIA_DRIVER_INSTALLER_DIR="/newNAS/Share/GPU_Server"
IFACE=$(route | grep default | awk '{print $8}')
IP=$(ifconfig $IFACE | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*')
PORT=$(curl -s -f http://$IAM_HOST/user/$USER/port)
INFO=$(lxc-info -n $USER)

function print_help {
    echo "========== Tips:"
    printf "Start your container: \e[96;1mssh $USER@$IP\e[0m\n"
    printf "Login your container: \e[96;1mssh $USER@$IP -p$PORT\e[0m\n"
    printf "Manually stop your container: \e[96;1mssh $USER@$IP stop\e[0m\n"
    printf "Take a snapshot: \e[96;1mssh $USER@$IP snapshot\e[0m\n"
    printf "Recover from snapshot: \e[96;1mssh $USER@$IP recover\e[0m\n"
    printf "Rebuild from template: \e[96;1mssh $USER@$IP rebuild\e[0m\n"
    printf "Use \e[96;1mscp\e[0m or \e[96;1mSFTP\e[0m to transfer data to your container\n"
    printf "SSD mounted at \e[96;1m/SSD\e[0m\n"
    printf "NAS mounted at \e[96;1m/NAS\e[0m\n"
    printf "See GPU load: \e[96;1mnvidia-smi\e[0m\n"
    printf "More detailed guide: \e[96;1;4mhttp://apex.sjtu.edu.cn/guides/50\e[0m\n"
}

function do_stop {
    echo "========== Stopping your container..."
    LXCIP=$(lxc-info -n $USER | grep 'IP:' | grep -Eo '[0-9].+')
    sudo iptables -t nat -D PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $LXCIP:22
    sudo iptables -t nat -D POSTROUTING -p tcp -d $LXCIP --dport 22 -j MASQUERADE
    lxc-stop -n $USER
    lxc-info -n $USER
}

function do_start {
    echo "$INFO" | grep RUNNING > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        # start the container
        echo "========== It seems that your container is not running"
        echo "========== Starting your container..."
        lxc-start -n $USER -d
        if [ $? -ne 0 ]; then
           echo "========== Fail. Please contact administrators"
           exit 1
        fi

        # wait until the container is up
        while true; do
            LXCIP=$(lxc-info -n $USER | grep 'IP:' | grep -Eo '[0-9].+')
            if [[ -z "$LXCIP" ]]; then
                sleep 0.1
            else
                break
            fi
        done
        echo "========== The container is up"

        # check if the nvidia driver matches the host's
        LXCROOT=/home/$USER/.local/share/lxc/$USER/rootfs
        HOST_DRIVER=$(readlink /usr/lib/x86_64-linux-gnu/libcuda.so.1 | sed 's/libcuda.so.//')
        LXC_DRIVER=$(readlink $LXCROOT/usr/lib/x86_64-linux-gnu/libcuda.so.1 | sed 's/libcuda.so.//')
        if [[ "$HOST_DRIVER" != "$LXC_DRIVER" ]]; then
            printf "NVIDIA driver version mismatch! Host=\e[96;1m$HOST_DRIVER\e[0m Yours=\e[96;1m$LXC_DRIVER\e[0m\n"
            INSTALLER="$NVIDIA_DRIVER_INSTALLER_DIR/NVIDIA-Linux-x86_64-$HOST_DRIVER.run"
            if [ ! -f "$INSTALLER" ]; then
                printf "Failed to find the installer at \e[96;1m$INSTALLER\e[0m"
                echo "You might need to manually install the driver"
            else
                printf "Installing the driver from \e[96;1m$INSTALLER\e[0m\n"
                sudo cp "$INSTALLER" $LXCROOT/nvidia-driver-installer.run
                sudo chown --reference $LXCROOT/bin/bash $LXCROOT/nvidia-driver-installer.run
                lxc-attach -n $USER -- sh /nvidia-driver-installer.run --no-kernel-module --silent
                sudo rm $LXCROOT/nvidia-driver-installer.run
                echo "Done! Trying nvidia-smi:"
                lxc-attach -n $USER -- nvidia-smi
                LXC_DRIVER=$(readlink $LXCROOT/usr/lib/x86_64-linux-gnu/libcuda.so.1 | sed 's/libcuda.so.//')
                if [[ "$HOST_DRIVER" != "$LXC_DRIVER" ]]; then
                    printf "NVIDIA driver version still mismatch! Host=\e[96;1m$HOST_DRIVER\e[0m Yours=\e[96;1m$LXC_DRIVER\e[0m\n"
                    echo "You might need to manually install the driver"
                else
                    printf "Successfully installed NVIDIA driver. Host=\e[96;1m$HOST_DRIVER\e[0m=Yours=\e[96;1m$LXC_DRIVER\e[0m\n"
                fi
            fi
        fi

        # forward ssh port
        sudo iptables -t nat -A PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $LXCIP:22
        sudo iptables -t nat -A POSTROUTING -p tcp -d $LXCIP --dport 22 -j MASQUERADE
        lxc-info -n $USER
    fi
    print_help
}

function do_snapshot {
    echo "$INFO" | grep RUNNING > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "========== It seems that your container is running"
        echo "========== You need to first stop your container"
        printf "Manually stop your container: \e[96;1mssh $USER@$IP stop\e[0m\n"
        return
    fi
    LXCROOT=/home/$USER/.local/share/lxc/$USER
    TOKEN=$(echo $(($(date +%s) / 300)) | md5sum | cut -c1-8)
    if [[ -z "$1" ]]; then
        echo "========== Calculating the size of rootfs..."
        sudo du -sh $LXCROOT/rootfs/
        echo "========== If you are sure to take a snapshot and save it to NAS,"
        echo "========== please run the following command in 5 minutes"
        printf "Confirm snapshot: \e[96;1mssh $USER@$IP snapshot $TOKEN\e[0m\n"
    elif [ "$1" == "$TOKEN" ]; then
        echo "========== Taking a snapshot..."
        SAVETO=$SNAPSHOT_PATH/$USER.tar.gz
        sudo tar --numeric-owner -czpf $SAVETO --directory=$LXCROOT rootfs
        printf "Saved to: \e[96;1m$SAVETO\e[0m\n"
        du -sh $SAVETO
        printf "Start your container: \e[96;1mssh $USER@$IP\e[0m\n"
    else
        echo "========== Invalid token"
        echo "========== Maybe you want to run the snapshot command again?"
        printf "Take a snapshot: \e[96;1mssh $USER@$IP snapshot\e[0m\n"
    fi
}


function do_recover {
    echo "$INFO" | grep RUNNING > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "========== It seems that your container is running"
        echo "========== You need to first stop your container"
        printf "Manually stop your container: \e[96;1mssh $USER@$IP stop\e[0m\n"
        return
    fi
    LXCROOT=/home/$USER/.local/share/lxc/$USER
    TOKEN=$(echo $(($(date +%s) / 300)) | md5sum | cut -c1-8)
    if [[ -z "$1" ]]; then
        echo "========== The whole rootfs will be replaced after recovery."
        echo "========== If you are sure to recover a snapshot from NAS,"
        echo "========== please run the following command in 5 minutes"
        FROM="$SNAPSHOT_PATH/$USER.tar.gz"
        printf "Confirm recover: \e[96;1mssh $USER@$IP recover $TOKEN $FROM\e[0m\n"
    elif [ "$1" == "$TOKEN" ]; then
        IAM_SUBUID=$(curl -s -f http://$IAM_HOST/user/$USER/subuid)
        if [ $? -ne 0 ]; then printf "Failed to get IAM information. Maybe visit \e[96;1;4mhttp://iam.apexlab.org/\e[0m\n"; exit 1; fi
        IAM_KEYS=$(curl -s -f http://$IAM_HOST/user/$USER/.ssh/authorized_keys)
        if [ $? -ne 0 ]; then printf "Failed to get IAM information. Maybe visit \e[96;1;4mhttp://iam.apexlab.org/\e[0m\n"; exit 1; fi
        IAM_SSHCONFIG=$(curl -s -f http://$IAM_HOST/user/$USER/.ssh/config)
        if [ $? -ne 0 ]; then printf "Failed to get IAM information. Maybe visit \e[96;1;4mhttp://iam.apexlab.org/\e[0m\n"; exit 1; fi

        echo "========== Recover from a snapshot..."
        FROM="$2"
        du -sh $FROM
        if [ $? -ne 0 ]; then
            echo "========== Snapshot does not exists."
            return
        fi
        sudo rm -rf $LXCROOT/rootfs
        sudo tar --same-owner -xf $FROM -C $LXCROOT

        echo "========== Fixing filesystem permission..."
        FILES_SUID=$(sudo find $LXCROOT -perm -4000)
        FILES_SGID=$(sudo find $LXCROOT -perm -2000)
        sudo chown -R $IAM_SUBUID:$IAM_SUBUID $LXCROOT/rootfs
        sudo chmod 7777 $LXCROOT/rootfs/tmp
        while read -r line; do sudo chmod u+s $line; done <<< "$FILES_SUID"
        while read -r line; do sudo chmod g+s $line; done <<< "$FILES_SGID"
        lxc-start -n $USER -d
        if [ ! -d "$LXCROOT/rootfs/home/$USER" ]; then
            echo "========== Adding user in the container..."
            unset XDG_SESSION_ID XDG_RUNTIME_DIR
            lxc-attach -n $USER -- useradd -m -G sudo -s /bin/bash $USER
            lxc-attach -n $USER -- mkdir /home/$USER/.ssh
            lxc-attach -n $USER -- touch /home/$USER/.ssh/authorized_keys
            lxc-attach -n $USER -- touch /home/$USER/.ssh/config
            lxc-attach -n $USER -- chown -R $USER:$USER /home/$USER/.ssh
            lxc-attach -n $USER -- chmod 700 /home/$USER/.ssh
            lxc-attach -n $USER -- chmod 600 /home/$USER/.ssh/authorized_keys
        fi
        lxc-attach -n $USER -- chown -R $USER:$USER /home/$USER
        lxc-stop -n $USER

        echo "========== Configuring..."
        HOSTNAME=$(hostname)
        echo "$HOSTNAME-$USER" | sudo tee $LXCROOT/rootfs/etc/hostname > /dev/null
        sudo sed -i "/127.0.1.1/d" $LXCROOT/rootfs/etc/hosts
        echo "127.0.1.1 $HOSTNAME-$USER" | sudo tee --append $LXCROOT/rootfs/etc/hosts > /dev/null
        echo "$IAM_KEYS" | sudo tee $LXCROOT/rootfs/home/$USER/.ssh/authorized_keys > /dev/null
        echo "$IAM_SSHCONFIG" | sudo tee $LXCROOT/rootfs/home/$USER/.ssh/config > /dev/null

        echo "========== Done"
        printf "Start your container: \e[96;1mssh $USER@$IP\e[0m\n"
    else
        echo "========== Invalid token"
        echo "========== Maybe you want to run the recover command again?"
        printf "Take a snapshot: \e[96;1mssh $USER@$IP recover\e[0m\n"
    fi
}

function do_rebuild {
    TOKEN=$(echo $(($(date +%s) / 300)) | md5sum | cut -c1-8)
    FROM="$SNAPSHOT_PATH/template.tar.gz"
    echo "========== The whole rootfs will be replaced after recovery."
    echo "========== If you are sure to recover a snapshot from NAS,"
    echo "========== please run the following command in 5 minutes"
    printf "Confirm recover: \e[96;1mssh $USER@$IP recover $TOKEN $FROM\e[0m\n"
}


printf "========== Hi, \e[96;1m$USER\e[0m\n"
echo "========== Welcome to APEX GPU Server (IP: $IP)"

if [[ -z "$PORT" ]]; then
    echo "Failed to get your allocated port."
    echo "If this problem cannot be solved by retrying, please contact administrators."
    exit 1
fi

echo "========== Your LXC Container Information:"
echo "$INFO"

args=($2)

if   [ "${args[0]}" == "stop" ];     then do_stop
elif [ "${args[0]}" == "help" ];     then print_help
elif [ "${args[0]}" == "snapshot" ]; then do_snapshot "${args[1]}"
elif [ "${args[0]}" == "recover" ];  then do_recover "${args[1]}" "${args[2]}"
elif [ "${args[0]}" == "rebuild" ];  then do_rebuild
elif [[ -z "${args[0]}" ]];          then do_start
else
    echo "========== Unknown command"
    print_help
    exit 1
fi
echo "========== Have a good day :-)"
