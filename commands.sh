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

try to read preconfigured server address from env file
if [ -f ".env" ]; then
   dstNode=`cat .env | xargs`
fi

function checkError {
    if [ $? -eq 0 ]; then
        printf "[$OK] $1 \n"
    else
        printf "[$FAIL] $1 \n"
        exit 1
    fi
}

function checkLoop {
    if [ $? -eq 0 ]; then
        printf "[$OK] $1 \n"
    else
        printf "[$FAIL] $1 \n"
        return 1
    fi
}

function checkWarn {
    if [ $? -eq 0 ]; then
        printf "[$OK] $1 \n"
    else
        printf "[$WARN] $2 \n"
        return 1
    fi
}

function checkContinue {
    read -p "$1, continue? [y] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
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

# loop
while true; do
done

# if the result of the previous command is true
if [ $? -eq 0 ]; 
then
    ...
else
    ...
fi

## VMID
# Get VMID
eval "qm list"

# Check, is VMID exists?
eval "qm list | awk ' \$1==$VMID ' | grep -q \"\" "

## VMID.conf
# copy tmp config
eval "cp /etc/pve/local/qemu-server/$VMID.conf /etc/pve/local/qemu-server/$VMID_NEW.tmp"
# get conf
VMID="180"; CONF=$(cat /etc/pve/local/qemu-server/$VMID.conf);
# transform conf  (VMID -> VMID_NEW)
VMID_NEW="901"; CONF_NEW=$(echo "$CONF" | sed "s/-$VMID-disk-/-$VMID_NEW-disk-/" -)
# save new conf
echo "$CONF_NEW" > /etc/pve/local/qemu-server/$VMID_NEW.conf


## ZFS
# Install pv
eval "apt install pv -y"
# generate snap name
SNAP=clone-tmp-`date +%s`
SNAP=clone-tmp-`date +%F_%H-%M-%S`
# get VOLUMES or datasets by VMID
VMID=180; VOLUMES=$(zfs list -H -o name | grep -e "-$VMID-disk") ; echo "$VOLUMES"
# create snapshot
zfs snapshot $VOL@$SNAP
# change VMID in VOL
VOL_NEW=$(echo $VOL | sed "s/-$VMID-disk/-$VMID_NEW-disk/" -)
# send snapshot
eval "zfs send -c $VOL@$SNAP | pv | zfs recv $VOL_NEW"


# inotify
function install-inotify {
    if ! dpkg -s inotify-tools >/dev/null ; then
        printf "[$WARN] inotify-tools not installed\n"
        apt update 
        apt install inotify-tools -y
    fi
}
while inotifywait -q -e close_write /etc/environment; do
    main >/dev/null
done

# read envivoments from file
function load {
    local FILE="${1}"
    if [[ -f  "${FILE}" ]]
    then 
        source "${FILE}"
    else
        touch "${FILE}"
    fi
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

    echo "Please input ${VARIABLE}"

    if [[ ! -v ${VARIABLE} ]];
    then
        eval ${VARIABLE}=""
    fi

    local VALUE="$(echo ${!1} | xargs)"

    read -e -p "> " -i "${VALUE}" ${VARIABLE}
    save ${VARIABLE} ".env"
    # echo "$VARIABLE is $VALUE"
}