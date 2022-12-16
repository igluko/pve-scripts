#!/bin/bash

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

function apt-install {
    if ! which "$1" >/dev/null
    then
        apt update -y || true
        apt install -y "$1"
    fi
}

#-----------------------START-----------------------#

# Install soft
apt-install fio
apt-install jq
apt-install fdisk 

DISKS="nvme0n1 nvme1n1"
PART="p4"

for DISK in $DISKS
do
    # Проверяем, что раздел существует на диске
    printf "\n${ORANGE}Проверяем, что раздел /dev/${DISK}${PART} существует${NC}\n"

    if ! [ -e /dev/${DISK}${PART} ]
    then
        printf "\n${RED}Раздел ${PART} не существует, создаем его${NC}\n"
        (
            echo n # Add a new partition
            echo   # Partition number
            echo   # First sector (Accept default: 1)
            echo   # Last sector (Accept default: varies)
            echo w # Write changes
        ) | fdisk /dev/${DISK}
    fi
    echo
    hostname
    cat /sys/class/block/${DISKS}/device/model
    cat /sys/class/block/${DISK}/device/serial
    cat /sys/devices/virtual/dmi/id/board_{vendor,name}



    function fio-run {
        fio --filename=/dev/${DISK}${PART} --group_reporting --output-format=json --runtime=60 --size=50G --ioengine=libaio --direct=1 --stonewall $*
    }
    
    printf "\n${GREEN}Заголовки:${NC}\n"
    echo -e "Seq-1m-Q8T1-Read \t KB/sec"
    echo -e "Seq-1m-Q8T1-Write \t KB/sec"
    echo -e "Seq-1m-Q1T1-Read \t KB/sec"
    echo -e "Seq-1m-Q1T1-Write \t KB/sec"

    echo -e "Seq-128k-Q32T1-Read \t KB/sec"
    echo -e "Seq-128k-Q32T1-Write \t KB/sec"

    echo -e "Rnd-4k-Q32T16-Read \t iops"
    echo -e "Rnd-4k-Q32T16-Write \t iops"
    echo -e "Rnd-4k-Q32T1-Read \t iops"
    echo -e "Rnd-4k-Q32T1-Write \t iops"
    echo -e "Rnd-4k-Q1T1-Read \t iops"
    echo -e "Rnd-4k-Q1T1-Write \t iops"

    printf "\n${GREEN}Результаты:${NC}\n"
    fio-run --name=Seq-1m-Q8T1-Read --rw=read --bs=1m --iodepth=8 | jq .jobs[0].read.bw
    fio-run --name=Seq-1m-Q8T1-Write --rw=write --bs=1m --iodepth=8 | jq .jobs[0].write.bw
    fio-run --name=Seq-1m-Q1T1-Read --rw=read --bs=1m --iodepth=1 | jq .jobs[0].read.bw
    fio-run --name=Seq-1m-Q1T1-Write --rw=write --bs=1m --iodepth=1 | jq .jobs[0].write.bw

    fio-run --name=Seq-128k-Q32T1-Read --rw=read --bs=128k --iodepth=32 | jq .jobs[0].read.bw
    fio-run --name=Seq-128k-Q32T1-Write --rw=write --bs=128k --iodepth=32 | jq .jobs[0].write.bw

    fio-run --name=Rnd-4k-Q32T16-Read --rw=read --bs=4k --iodepth=32 --numjobs=16 | jq .jobs[0].read.iops | sed 's/\..*//'
    fio-run --name=Rnd-4k-Q32T16-Write --rw=write --bs=4k --iodepth=32 --numjobs=16 | jq .jobs[0].write.iops | sed 's/\..*//'
    fio-run --name=Rnd-4k-Q32T1-Read --rw=read --bs=4k --iodepth=32 | jq .jobs[0].read.iops | sed 's/\..*//'
    fio-run --name=Rnd-4k-Q32T1-Write --rw=write --bs=4k --iodepth=32 | jq .jobs[0].write.iops | sed 's/\..*//'
    fio-run --name=Rnd-4k-Q1T1-Read --rw=read --bs=4k --iodepth=1 | jq .jobs[0].read.iops | sed 's/\..*//'
    fio-run --name=Rnd-4k-Q1T1-Write --rw=write --bs=4k --iodepth=1 | jq .jobs[0].write.iops | sed 's/\..*//'

    echo
done

