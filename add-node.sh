#!/bin/bash

###
# This script prevents Hetzner Abuse Message : MAC-Errors
###

# Helpful to read output when debugging
# set -x

#https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color
OK="${GREEN} done ${NC}"
FAIL="${RED}failed${NC}"
WARN="[${ORANGE}warning${NC}]"

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
	eval "$1"
    printf "[$OK] $1 \n"
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

# read envivoments from file
function load {
    local FILE="${1}"
    source "${FILE}"
}

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

# make sure that variable is set
# echo "Please input destination XXX"
function update {
    local VARIABLE="${1}"
    local VALUE="$(echo ${!1} | xargs)"

    echo "Please input ${VARIABLE}"

    if [[ ! -v ${VARIABLE} ]];
    then
        eval ${VARIABLE}=""
    fi

    read -e -p "> " -i "${VALUE}" ${VARIABLE}
    save ${VARIABLE} ".env"
}

function 1-step {

    # 0 BIOS
    echo "Please check BIOS"
    read -e -p "> " -i "ok"

    # 1 ISO
    echo "Please activate RescueCD in Hetzner Robot panel and Execute an automatic hardware reset"
    read -e -p "> " -i "ok"

    eval ${SSH} "wget -N http://download.proxmox.com/iso/proxmox-ve_7.2-1.iso"

    # ID_NET_NAME_PATH=$($SSH "udevadm test /sys/class/net/eth0 2>/dev/null | grep ID_NET_NAME_PATH | cut -s -d = -f 2-")
    # echo "$ID_NET_NAME_PATH"
    printf "${WARN} " 
    echo "IP = ${DST_HOST}"
    # printf "${WARN} " 
    # echo "ID_NET_NAME_PATH = ${ID_NET_NAME_PATH}"

    # generate random password
    VNC_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo '')
    printf "${WARN} VNC Password is ${GREEN}${VNC_PASSWORD}${NC}\n"

    eval $SSH "pkill qemu-system-x86 || true"
    $SSH "printf \"change vnc password\n%s\n\" ${VNC_PASSWORD} | qemu-system-x86_64 -enable-kvm -smp 4 -m 4096 -boot once=d -cdrom ./proxmox-ve_7.2-1.iso -drive file=/dev/nvme0n1,format=raw,cache=none,index=0,media=disk -drive file=/dev/nvme1n1,format=raw,cache=none,index=1,media=disk -vnc 0.0.0.0:0,password -monitor stdio" >/dev/null &
   
    echo "Please open VNC console, install PVE and press Next"
    read -e -p "> " -i "Next" DST_HOST
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
    printf '\e]8;;https://'${DST_HOST}':8006\e\\https://'${DST_HOST}':8006\e]8;;\e\\\n' 
}

function 2-step {
    update "DST_HOSTNAME"

    
}

# Setup if interacive mode  Suppress output if non-interacive mode
if [ -t 1 ] ; then
    load "${SCRIPTPATH}/.env"

    # make sure that variable is set
    if [[ ! -v DST_HOST ]];
    then
        DST_HOST=""
    fi
    echo "Please input destination IP"
    read -e -p "> " -i "${DST_HOST}" DST_HOST
    save DST_HOST ".env"

    DST_USER="root"
    DST="${DST_USER}@${DST_HOST}"
    SSH="ssh -C ${DST}"

    ssh-copy-id ${DST}

    if ! $SSH "[[ -d /etc/pve ]]"
    then
        1-step
    else
        2-step
    fi

    # main
    #run "cron-update"
else
    main >/dev/null
fi