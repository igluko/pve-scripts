#!/bin/bash

###
# This script prepares a new PVE node
# Tested on Hetzner AX-101 servers
###

# Helpful to read output when debugging
# set -x

#https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Strict mode
# set -eEuo pipefail
set -eEu
trap 'printf "${RED}Failed on line: $LINENO at command:${NC}\n$BASH_COMMAND\nexit $?\n"' ERR
# IFS=$'\n\t'

# read envivoments
source  /etc/environment
# get real path to script
SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`
# add binary folders to local path
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

function run {
    printf "\n${GREEN}$*${NC}\n"
	# eval "$*"
    $SSH "$*"
}

# function cron-update {
    # TASK="@reboot $SCRIPT"
    # if crontab -l 2>/dev/null | grep -F -q "$TASK"
    # then 	
    #     echo "task already has been added to crontab"
    # else
    #     (crontab -l 2>/dev/null; echo "$TASK") | crontab -
    # fi
# }

# Read variable from file
function load {
    local FILE="${1}"
    if [[ -f  "${FILE}" ]]
    then 
        source "${FILE}"
    else
        touch "${FILE}"
    fi
}

# Save variable to file
function save {
    local VARIABLE="${1}"
    local VALUE="$(echo ${!1} | xargs)"
    local FILE="${2}"

    if grep -q ^${VARIABLE}= $FILE 2>/dev/null
    then
        eval "sed -i -E 's/${VARIABLE}=.*/${VARIABLE}=\"${VALUE}\"/' $FILE"
    else
        echo "${VARIABLE}=\"${VALUE}\"" >> $FILE
    fi
}

# Update variable in file from stdin
function update {
    local VARIABLE="${1}"
    local FILE="${SCRIPTPATH}/.env"

    load ${FILE}

    if [[ ! -v ${VARIABLE} ]];
    then
        eval ${VARIABLE}=""
    fi
    local VALUE="$(echo ${!1} | xargs)"

    printf "\n${ORANGE}Please input ${VARIABLE}${NC}\n"
    read -e -p "> " -i "${VALUE}" ${VARIABLE}
    save ${VARIABLE} ${FILE}
    # echo "$VARIABLE is $VALUE"
}

function apt-install {
    if ! which "$1" >/dev/null
    then
        apt update -y || true
        apt install -y "$1"
    fi
}

function 1-step {
    printf "${ORANGE}"
    echo "Start 2 step"
    printf "${NC}"

    # 0 BIOS
    echo "Please check BIOS"
    read -e -p "> " -i "ok"

    # 1 ISO
    echo "Please activate RescueCD in Hetzner Robot panel and Execute an automatic hardware reset"
    read -e -p "> " -i "ok"

    ISO="proxmox-ve_7.3-1.iso"
    eval ${SSH} "wget -N http://download.proxmox.com/iso/$ISO"

    # ID_NET_NAME_PATH=$($SSH "udevadm test /sys/class/net/eth0 2>/dev/null | grep ID_NET_NAME_PATH | cut -s -d = -f 2-")
    # echo "$ID_NET_NAME_PATH"
    printf "${WARN} " 
    echo "IP = ${DST_IP}"
    # printf "${WARN} " 
    # echo "ID_NET_NAME_PATH = ${ID_NET_NAME_PATH}"

    # generate random password
    VNC_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo '')
    printf "${WARN} VNC Password is ${GREEN}${VNC_PASSWORD}${NC}\n"

    eval $SSH "pkill qemu-system-x86 || true"
    $SSH "printf \"change vnc password\n%s\n\" ${VNC_PASSWORD} | qemu-system-x86_64 -enable-kvm -smp 4 -m 4096 -boot once=d -cdrom ./$ISO -drive file=/dev/nvme0n1,format=raw,cache=none,index=0,media=disk -drive file=/dev/nvme1n1,format=raw,cache=none,index=1,media=disk -vnc 0.0.0.0:0,password -monitor stdio" >/dev/null &
   
    echo "Please open VNC console, install PVE and press Next"
    read -e -p "> " -i "Next"
    eval $SSH "pkill qemu-system-x86 || true"

    $SSH zpool version

    if ! $SSH 'zpool list | grep -v "no pools available"'
    then
        $SSH "zpool import -f -N rpool"
    fi

    $SSH "zfs set mountpoint=/mnt rpool/ROOT/pve-1"
    $SSH "zfs mount rpool/ROOT/pve-1 | true"

    printf "${GREEN}"
    for i in $($SSH "ls /sys/class/net/ | grep -v lo")
    do
        $SSH "udevadm test /sys/class/net/$i 2>/dev/null | grep ID_NET_NAME_"
    done
    printf "${NC}"


    INTERFACES="/mnt/etc/network/interfaces"
    IP=$($SSH "cat ${INTERFACES} | grep -oE address.* | cut -s -d \" \" -f 2- | cut -s -d \"/\" -f 1")
    GATEWAI=$($SSH "cat ${INTERFACES} | grep -oE gateway.* | cut -s -d \" \" -f 2-")

    # IF_NAME=$(echo "${ID_NET_NAME_PATH}" | head -n 1)
    echo "Please enter INTERFACE NAME:"
    read -e -p "> " -i "" IF_NAME
    echo "Please enter IP:"
    read -e -p "> " -i "$IP" IP
    echo "Please enter GATEWAY:"
    read -e -p "> " -i "$GATEWAI" GATEWAI



    $SSH "sed -i -E \"s/iface ens3 inet manual/iface ${IF_NAME} inet manual/\" ${INTERFACES}"
    $SSH "sed -i -E \"s/bridge-ports .*/bridge-ports ${IF_NAME}/\"  ${INTERFACES}" 
    $SSH "sed -i -E \"s/address .*/address ${IP}\/32/\" ${INTERFACES}"
    $SSH "sed -i -E \"s/gateway .*/gateway ${GATEWAI}/\"  ${INTERFACES}"

    $SSH "zfs set mountpoint=/ rpool/ROOT/pve-1"
    $SSH "zpool export rpool"

    $SSH "reboot" 2>/dev/null | true
    printf "${GREEN}"
    echo "Proxmox will be enabled at this link in 2 minutes"
    printf "${NC}"
    printf '\e]8;;https://'${DST_IP}':8006\e\\https://'${DST_IP}':8006\e]8;;\e\\\n' 
}

function 2-step {
    printf "${ORANGE}"
    echo "Start 2 step"
    printf "${NC}"
    
    DST_HOSTNAME=$(${SSH} hostname)

    # Шаг 2 - firewall

    local FILE="/etc/pve/firewall/cluster.fw"
    if ! grep ${DST_IP} ${FILE}
    then
        echo "IN ACCEPT -source ${DST_IP} -log nolog # ${DST_HOSTNAME}" >> ${FILE}
    fi

    if ! ${SSH} [[ -f ${FILE} ]]
    then
        ${SSH} "mkdir -p /etc/pve/firewall"
    fi

    cat ${FILE} | ${SSH} "cat > ${FILE}"

    # Шаг 3 - документация

    ${SSH} "ip addr"
    ${SSH} "cat /sys/class/block/*/device/{model,vendor} 2>/dev/null ; true"
    ${SSH} "cat /sys/devices/virtual/dmi/id/board_{vendor,name} 2>/dev/null ; true"
    ${SSH} "udevadm test /sys/class/net/eth0 2>/dev/null | grep ID_NET_NAME_ ; true"

    echo "Please update Documentation"
    read -e -p "> " -i "ok"

    # Шаг 4 - hosts
    local FILE="/etc/hosts"
    if ! grep ${DST_IP} ${FILE}
    then
        echo "${DST_IP} ${DST_HOSTNAME}.local ${DST_HOSTNAME}" >> ${FILE}
    fi

    cat ${FILE} | ${SSH} "cat > ${FILE}"

    # Шаг 5 - Отображать имя хоста во вкладке
    local FILE=".bashrc"
    if ! $SSH "grep \"If this is an xterm set the title to host:dir\" ${FILE}"
    then
        cat "${SCRIPTPATH}/${FILE}" | ${SSH} "cat >> ${FILE}"
    fi

    # Шаг 7 - Лицензии и обновления
    echo "Please install PVE Licence"
    read -e -p "> " -i "ok"

    #  Меняем RU репозитории на обычные, RU еле шевелятся:
    $SSH "sed -i s/\.ru\./\./ /etc/apt/sources.list"

    # В заключении обновляем пакеты на сервере:
    $SSH "apt update ; apt dist-upgrade -y"

    # Включаем новые возможности zfs, если таковые есть
    $SSH "zpool upgrade rpool"

    # Шаг 9 - Шифрование данных кластера

    if ${SSH} "zfs get encryption -p -H rpool/data | grep -q off"
    then
        #Создадим файл с ключом шифрования в папке /tmp
        local FILE="/tmp/passphrase"
        cat ${FILE} | ${SSH} "cat > ${FILE}"
        $SSH "zfs destroy rpool/data; true"
        $SSH "zfs create -o encryption=on -o keyformat=passphrase -o keylocation=file:///tmp/passphrase rpool/data"
    fi

    # Шаг 8 - Настройка ZFS
    ${SSH} "zpool set autotrim=on rpool"
    ${SSH} "zfs set atime=off rpool"
    ${SSH} "zfs set compression=zstd-fast rpool"
    ${SSH} "pvesm set local-zfs --blocksize 16k"
    ${SSH} "echo 10779361280 >> /sys/module/zfs/parameters/zfs_arc_sys_free"

    local FILE="/etc/modprobe.d/zfs.conf"
    ${SSH} "echo \"options zfs zfs_arc_sys_free=10779361280\" > ${FILE}"

    if ! $SSH "grep \"options zfs zfs_arc_sys_free=10779361280\" ${FILE}"
    then
        ${SSH} "update-initramfs -u"
    fi
    ${SSH} "zfs set primarycache=metadata rpool"



    # # Шаг X - Download virtio-win.iso
    # # Latest:
    # ${SSH}  "wget -N --content-disposition --directory-prefix=/var/lib/vz/template/iso/ https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
    # # Latest for windows 7:
    # ${SSH}  "wget -N -O /var/lib/vz/template/iso/virtio-win-0.1.173-win7.iso https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.173-9/virtio-win-0.1.173.iso"

    # Шаг 11 - добавление ноды в кластер
    echo "Please take snapshot on ALL nodes, and add node to cluster"
    read -e -p "> " -i "ok"
    #$SSH "zfs snapshot -r rpool@before_cluster-${date +%s}"

    exit
    # Шаг 13.1 - Патч Proxmox для работы с шифрованным ZFS и pve-zsync
    ${SSH} "apt install -y patch"
    ${SSH} "patch /usr/share/perl5/PVE/Storage/ZFSPoolPlugin.pm ZFSPoolPlugin.pm.patch"

}

#-----------------------START-----------------------#

# Check terminal
if ! [[ -t 1 ]]
then
    echo "This script must be running in interactive mode"
    exit 1
fi

# Setup SSH
update "DST_IP"
DST_USER="root"
DST="${DST_USER}@${DST_IP}"
SSH="ssh -C -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q ${DST}"

# Copy public key to authorized_keys
if ! ${SSH} "true"
then
    echo ""
    FILE='/root/.ssh/id_rsa.pub'
    if [ -f $FILE ]; then
        ssh-copy-id -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ${FILE} ${DST}
    else
        echo "$FILE not exist"
        exit 1
    fi
fi

# check step
if ! $SSH "[[ -d /etc/pve ]]"
then
    1-step
else
    2-step
fi