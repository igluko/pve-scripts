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

for disk in ${DISKS}
do
    KVM_DISKS+="-drive file=/dev/${disk},format=raw,cache=none,index=${DISK_INDEX},media=disk "
    ((DISK_INDEX+=1))
done

if Q "Install PVE?"
then
    URL=$(curl -s https://www.proxmox.com/en/downloads/category/iso-images-pve | grep -o "/en/downloads?.*" | head -n1 | sed 's/".*//')
    WGET="wget --show-progress -N --progress=bar:force --content-disposition"
    ${WGET} "https://www.proxmox.com$URL"
    ISO=$(ls proxmox-ve*)
elif Q "Install PBS?"
then
    URL=$(curl -s https://www.proxmox.com/en/downloads/category/iso-images-pbs | grep -o "/en/downloads?.*" | head -n1 | sed 's/".*//')
    WGET="wget --show-progress -N --progress=bar:force --content-disposition"
    ${WGET} "https://www.proxmox.com$URL"
    ISO=$(ls proxmox-backup-server*)
else
    exit 0
fi

# generate random password
VNC_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo '')
printf "${ORANGE} VNC Password is ${GREEN}${VNC_PASSWORD}${NC}\n"

# Start KVM
eval SSH "pkill qemu-system-x86 || true"
printf "${RED} Please open VNC console to ${SSH_IP}, install PVE and press Next${NC}\n"
SSH "printf \"change vnc password\n%s\n\" ${VNC_PASSWORD} | qemu-system-x86_64 -enable-kvm -smp 4 -m 4096 -boot once=d -cdrom ./$ISO ${KVM_DISKS} -vnc 0.0.0.0:0,password -monitor stdio" >/dev/null &

read -e -p "> " -i "Next"
eval SSH "pkill qemu-system-x86 || true"

SSH zpool version

if ! SSH 'zpool list | grep -v "no pools available"'
then
    SSH "zpool import -f -N rpool"
fi

SSH "zfs set mountpoint=/mnt rpool/ROOT/pve-1"
SSH "zfs mount rpool/ROOT/pve-1 | true"

printf "${GREEN}"
for i in $(SSH "ls /sys/class/net/ | grep -v lo")
do
    SSH "udevadm test /sys/class/net/$i 2>/dev/null | grep ID_NET_NAME_"
done
printf "${NC}"


INTERFACES="/mnt/etc/network/interfaces"
IP=$(SSH "cat ${INTERFACES} | grep -oE address.* | cut -s -d \" \" -f 2- | cut -s -d \"/\" -f 1")
GATEWAI=$(SSH "cat ${INTERFACES} | grep -oE gateway.* | cut -s -d \" \" -f 2-")

# IF_NAME=$(echo "${ID_NET_NAME_PATH}" | head -n 1)
echo "Please enter INTERFACE NAME:"
read -e -p "> " -i "" IF_NAME
echo "Please enter IP:"
read -e -p "> " -i "$IP" IP
echo "Please enter GATEWAY:"
read -e -p "> " -i "$GATEWAI" GATEWAI

eval "sed -i -E \"s/iface ens3 inet manual/iface ${IF_NAME} inet manual/\" ${INTERFACES}"
eval "sed -i -E \"s/bridge-ports .*/bridge-ports ${IF_NAME}/\"  ${INTERFACES}" 
eval "sed -i -E \"s/address .*/address ${IP}\/32/\" ${INTERFACES}"
eval "sed -i -E \"s/gateway .*/gateway ${GATEWAI}/\"  ${INTERFACES}"

eval "zfs set mountpoint=/ rpool/ROOT/pve-1"
eval "zpool export rpool"


H1 "Proxmox will be enabled at this link in 2 minutes after reboot"

H1 "PVE -   https://${IP}:8006"
H1 "PBS -   https://${IP}:8007"

Q "reboot?" && reboot