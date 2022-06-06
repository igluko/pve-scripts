#!/bin/bash

#https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
#printf "I ${RED}love${NC} Stack Overflow\n"
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color
OK="${GREEN} ok ${NC}"
FAIL="${RED}fail${NC}"
WARN="${ORANGE}warn${NC}"

function checkError {
    if [ $? -eq 0 ]; then
        printf "[$OK] $1 \n"
    else
        printf "[$FAIL] $1 \n"
        exit 1
    fi
}

function checkYesNo {
    while true; do
    printf "${RED}"
    read -p "$1? [y/n] " -n 1 -r
    printf "${NC}\n"
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0
        elif [[ $REPLY =~ ^[Nn]$ ]]; then
            return 1
        fi
    done
}

# Install pv
eval "apt install pv -y"
checkError "apt install pv -y"

# Get VMID
eval "qm list"
checkError "qm list"

read -p "Enter the VMID to clone: " VMID

# Check, is VMID exists?
eval "qm list | awk ' \$1==$VMID ' | grep -q \"\" "
checkError "check : VMID $VMID exists?"

# Get new VMID
VMID_NEW=`pvesh get /cluster/nextid`
checkError "pvesh get /cluster/nextid"

while true; do
    read -e -p "Enter NEW VMID: " -i $VMID_NEW VMID_NEW
    # check is VMID available
    eval "grep -Eq '.$VMID_NEW.:' /etc/pve/.vmlist"
    if [ $? -eq 0 ]; 
    then
        printf "[$FAIL] ID $VMID_NEW already in use! \n"
        continue
    else
        printf "[$OK] ID $VMID_NEW is available on target server \n"
        break
    fi
done

# get conf
CONF=$(cat /etc/pve/local/qemu-server/$VMID.conf);
checkError "get conf to variable"

# transform conf  (VMID -> VMID_NEW)
CONF_NEW=$(echo "$CONF" | sed "s/-$VMID-disk-/-$VMID_NEW-disk-/" -)
checkError "transform conf  (VMID -> VMID_NEW)"

# generate snap name
SNAP=clone-tmp-`date +%F_%H-%M-%S`
checkError "generate snap name ($SNAP)"


# get volumes or datasets by VMID
VOLUMES=$(zfs list -H -o name | grep -e "-$VMID-disk")
checkError "get volumes or datasets by VMID $VMID"

for VOL in $VOLUMES
do
    # create snapshot
    eval "zfs snapshot $VOL@$SNAP"
    checkError "zfs snapshot $VOL@$SNAP"
    # generate new VOLUME name
    VOL_NEW=$(echo $VOL | sed "s/-$VMID-disk/-$VMID_NEW-disk/" -)
    checkError "generate new VOLUME name ($VOL_NEW)"
    # send snapshot
    eval "zfs send -c $VOL@$SNAP | pv | zfs recv $VOL_NEW"
    checkError "zfs send -c $VOL@$SNAP | pv | zfs recv $VOL_NEW"
done

# save new conf
echo "$CONF_NEW" > /etc/pve/local/qemu-server/$VMID_NEW.conf
checkError "save new conf"

if checkYesNo "Change MAC and UUIDs?"
then
    # Set new MAC address
    eval 'qm config $VMID_NEW | grep net.: | sed -E "s/(net[0-9]):(.*)=(..:..:..:..:..:..)(.*)/-\1\2\4/" | xargs -n2 qm set $VMID_NEW'
    checkError "Set new MAC address"

    # Set new VM Generation ID
    eval 'qm set $VMID_NEW --vmgenid 1'
    checkError "Set new VM Generation ID address"

    # Set new SMBIOS UUID
    UUID=$(cat /proc/sys/kernel/random/uuid)
    eval 'qm set $VMID_NEW --smbios1 uuid=$UUID'
    checkError "Set new SMBIOS UUID"
fi




