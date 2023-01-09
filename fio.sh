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
printf "\n${GREEN}apt install${NC}\n"
apt-install fio
apt-install jq
apt-install fdisk


DISKS="nvme0n1 nvme1n1"
PART="127"

if [[ $# -ne 0 ]]
then
    DISKS=$*
fi

# if [[ $# -eq 0 ]]
# then
#     DISKS="nvme0n1 nvme1n1"
# else
#     DISKS=$*
# fi

# PART="127"

for DISK in $DISKS
do
    # Проверяем, что диск существует
    printf "\n${ORANGE}Проверяем, что диск  /dev/${DISK} существует${NC}\n"
    if ! lsblk | grep -q ${DISK}
    then
        printf "${RED}Ошибка: диск /dev/${DISK} не найден${NC}\n"
        # Выводим информацию о текущих дисках
        printf "\n${ORANGE}Информация о текущих NVME дисках${NC}\n"
        lsblk | grep nvme
        continue
    fi

    # # Проверяем, что раздел существует на диске. Если нет - создаем раздел.
    # printf "\n${ORANGE}Проверяем, что раздел /dev/${DISK}p${PART} существует${NC}\n"
    # if ! lsblk | grep -q ${DISK}p${PART}
    # then
    #     printf "\n${ORANGE}Раздел ${PART} не существует, создаем его${NC}\n"
    #     (
    #         echo n        # Add a new partition
    #         echo ${PART}  # Partition number
    #         echo          # First sector (Accept default: 1)
    #         echo          # Last sector (Accept default: varies)
    #         echo w        # Write changes
    #     ) | fdisk /dev/${DISK}

    #     # Снова проверяем, что раздел существует на диске
    #     printf "\n${ORANGE}Снова проверяем, что раздел /dev/${DISK}p${PART} существует${NC}\n"
    #     if ! lsblk | grep -q ${DISK}p${PART}
    #     then
    #         printf "${RED}Ошибка: не удалось создать раздел /dev/${DISK}p${PART}${NC}\n"
    #         continue
    #     fi
    # fi

    # Проверяем, что раздел существует на диске.
    printf "\n${ORANGE}Проверяем, что раздел /dev/${DISK}p${PART} существует${NC}\n"
    if ! lsblk | grep -q ${DISK}p${PART}
    then
        printf "\n${RED}Раздел ${PART} не существует, пожалуйста создайте его перед запуском теста${NC}\n"
        continue
    fi

    # Выводим информацию о диске и материнской плате
    printf "\n${GREEN}Информация:${NC}\n"
    hostname
    cat /sys/class/block/${DISK}/device/model
    cat /sys/class/block/${DISK}/device/serial
    cat /sys/devices/virtual/dmi/id/board_{vendor,name}

    function fio-run {
        fio --filename=/dev/${DISK}p${PART} --group_reporting --output-format=json --time_based --runtime=60 --size=100% --ioengine=libaio --direct=1 --stonewall $*
    }

    # Выводим заголовки тестов
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

    # Выводим результаты тестов
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

    # # Удаляем тестовый раздел
    # printf "\n${ORANGE}Удаляем тестовый раздел /dev/${DISK}p${PART}${NC}\n"
    # (
    #     echo d       # Add a new partition
    #     echo ${PART} # Partition number
    #     echo w       # Write changes
    # ) | fdisk /dev/${DISK}
done

