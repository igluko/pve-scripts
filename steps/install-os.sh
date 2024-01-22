#!/bin/bash

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
# load functions
source $SCRIPT_PATH/../FUNCTIONS
IFS=$' \n\t'

H1 "hostnamectl"
hostnamectl
H1 "ip addr"
ip addr | grep -E 'altname|global '
H1 "ip route"
ip route | grep default

DISKS=$(lsblk -o NAME,SIZE,TYPE | grep disk | awk '{print $1}')
KVM_DISKS=""
DISK_INDEX=0

IP=$(hostname -I | awk '{print $1}')

for disk in ${DISKS}
do
    KVM_DISKS+="-drive file=/dev/${disk},format=raw,cache=none,index=${DISK_INDEX},if=virtio,media=disk "
    ((DISK_INDEX+=1))
done

# Check for EFI or MBR boot mode
if [ -d /sys/firmware/efi ]; then
    H1 "Текущий режим загрузки: EFI"
    BOOT_MODE="efi"
    QEMU_MACHINE_TYPE="q35"
else
    H1 "Текущий режим загрузки: MBR"
    BOOT_MODE="mbr"
    QEMU_MACHINE_TYPE="pc"
fi

function START_KVM {
    # generate random password
    VNC_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 || true ; echo '')
    printf "${ORANGE} VNC Password is ${GREEN}${VNC_PASSWORD}${NC}\n"

    # Start KVM
    pkill qemu-system-x86 || true
    H1 "Please open VNC console to ${IP}, install PVE and press Next"
    printf "change vnc password\n%s\n" ${VNC_PASSWORD} | qemu-system-x86_64 -enable-kvm -smp 4 -m 4096 -boot once=d -cdrom ./$ISO ${KVM_DISKS} -M ${QEMU_MACHINE_TYPE} -vnc 0.0.0.0:0,password -monitor stdio &>/dev/null &

    read -e -p "> " -i "Next"
}

function DOWNLOAD_ISO {
    URL=$1
    WGET="wget --show-progress -N --progress=bar:force --content-disposition"
    ${WGET} "$URL"
    ISO=$(basename $URL)
}

if Q "Install PVE?"
then
    URL=$(curl -s https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso | grep -o 'href="[^"]*">Download</a>' | sed -E 's/href="([^"]*)">Download<\/a>/\1/' | head -n1)
    echo "$URL"
    if [ -z "$URL" ]; then
        echo "Could not find ISO on the website. Please enter URL to download PVE ISO:"
        read -e -p "> " CUSTOM_URL
        DOWNLOAD_ISO "$CUSTOM_URL"
    else
        DOWNLOAD_ISO "$URL"
    fi
    START_KVM
elif Q "Install PBS?"
then
    URL=$(curl -s https://www.proxmox.com/en/downloads/category/iso-images-pbs | grep -o "/en/downloads?.*" || true | head -n1 | sed 's/".*//')
    if [ -z "$URL" ]; then
        echo "Could not find ISO on the website. Please enter URL to download PBS ISO:"
        read -e -p "> " CUSTOM_URL
        DOWNLOAD_ISO "$CUSTOM_URL"
    else
        DOWNLOAD_ISO "$URL"
    fi
    START_KVM
fi

if Q "Change INTERFACE name or IP?"
then
    pkill qemu-system-x86 || true
    zpool version
    if ! zpool list | grep -v "no pools available"
    then
        zpool import -f -N rpool
    fi

    ZFS_ROOT=$(zfs list -o name -H | grep rpool/ROOT/...-1)

    # -o options An optional, comma-separated list of mount options to use temporarily for the duration of the mount
    # Not worked
    # https://github.com/openzfs/zfs/issues/4553
    # eval "zfs mount -o mountpoint=/mnt ${ZFS_ROOT} || true"
    zfs set mountpoint=/mnt ${ZFS_ROOT}
    zfs mount ${ZFS_ROOT} || true

    printf "${GREEN}"
    for i in $(ls /sys/class/net/ | grep -v lo)
    do
        udevadm test /sys/class/net/$i 2>/dev/null | grep ID_NET_NAME_
    done
    printf "${NC}"


    FILE="/mnt/etc/network/interfaces"
    IP=$(eval "cat ${FILE} | grep -oE address.* | cut -s -d \" \" -f 2- | cut -s -d \"/\" -f 1")
    GATEWAI=$(eval "cat ${FILE} | grep -oE gateway.* | cut -s -d \" \" -f 2-")

    # IF_NAME=$(echo "${ID_NET_NAME_PATH}" | head -n 1)
    echo "Please enter INTERFACE NAME:"
    read -e -p "> " -i "" IF_NAME
    echo "Please enter IP:"
    read -e -p "> " -i "$IP" IP
    echo "Please enter GATEWAY:"
    read -e -p "> " -i "$GATEWAI" GATEWAI

    eval "sed -i -E \"s/ens3/${IF_NAME}/\" ${FILE}"
    eval "sed -i -E \"s/bridge-ports .*/bridge-ports ${IF_NAME}/\"  ${FILE}" 
    eval "sed -i -E \"s/address .*/address ${IP}\/32/\" ${FILE}"
    eval "sed -i -E \"s/gateway .*/gateway ${GATEWAI}/\"  ${FILE}"
   
    H1 "cat ${FILE}"
    cat "${FILE}"

    eval "zfs set mountpoint=/ ${ZFS_ROOT}"
    eval "zpool export rpool"

    H1 "Proxmox will be enabled at this link in 2 minutes after reboot"

    H1 "PVE -   https://${IP}:8006"
    H1 "PBS -   https://${IP}:8007"

    Q "reboot?" && reboot

fi