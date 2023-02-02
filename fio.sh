#!/bin/bash

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
# load functions
source $SCRIPT_PATH/FUNCTIONS

# Install soft
printf "\n${GREEN}apt install${NC}\n"
INSTALL fio
INSTALL jq
INSTALL fdisk
INSTALL nvme-cli

# Выводим информацию о хосте и материнской плате
printf "\n${GREEN}Информация:${NC}\n"
hostname
cat /sys/devices/virtual/dmi/id/board_{vendor,name} || true
dmidecode -t memory | grep Speed | head -2 | xargs -r || true
nvme list

if [[ $# -eq 0 ]]
then
    printf "\n${RED}Usage:${NC}\n"
    printf "fio.sh <disk1> [disk2]\n\n"
    exit
fi

DISKS=$*

for DISK in $DISKS
do
    # Если это не диск, а папка
    if [[ -d $DISK ]]
    then
        # Задаем путь теста
        TEST_PATH="--directory=${DISK}"
        SIZE="--size=100G"
    else
        # Проверяем, что диск существует
        printf "\n${ORANGE}Проверяем, что диск (раздел) ${DISK} существует${NC}\n"
        if ! (ls -l /dev/${DISK} || ls -l /dev/disk/*/${DISK}) 2>/dev/null
        then
            printf "${RED}Ошибка: диск (раздел) ${DISK} не найден${NC}\n"
            continue
        fi

        DISK_PATH=$(ls /dev/${DISK} 2>/dev/null || ls /dev/disk/*/${DISK} 2>/dev/null)

        # Задаем путь теста
        TEST_PATH="--filename=${DISK_PATH}"
        SIZE="--size=100%"
    fi

    Q "WARNING! This test overwrite data on disk! Continue?" || exit

    function fio-run {
        fio ${TEST_PATH} --name=fio.data --group_reporting --output-format=json --time_based --runtime=60 ${SIZE} --ioengine=libaio --direct=1 --stonewall $*
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
    fio-run --rw=read --bs=1m --iodepth=8 | jq .jobs[0].read.bw
    fio-run --rw=write --bs=1m --iodepth=8 | jq .jobs[0].write.bw
    fio-run --rw=read --bs=1m --iodepth=1 | jq .jobs[0].read.bw
    fio-run --rw=write --bs=1m --iodepth=1 | jq .jobs[0].write.bw

    fio-run --rw=read --bs=128k --iodepth=32 | jq .jobs[0].read.bw
    fio-run --rw=write --bs=128k --iodepth=32 | jq .jobs[0].write.bw

    fio-run --rw=read --bs=4k --iodepth=32 --numjobs=16 | jq .jobs[0].read.iops | sed 's/\..*//'
    fio-run --rw=write --bs=4k --iodepth=32 --numjobs=16 | jq .jobs[0].write.iops | sed 's/\..*//'
    fio-run --rw=read --bs=4k --iodepth=32 | jq .jobs[0].read.iops | sed 's/\..*//'
    fio-run --rw=write --bs=4k --iodepth=32 | jq .jobs[0].write.iops | sed 's/\..*//'
    fio-run --rw=read --bs=4k --iodepth=1 | jq .jobs[0].read.iops | sed 's/\..*//'
    fio-run --rw=write --bs=4k --iodepth=1 | jq .jobs[0].write.iops | sed 's/\..*//'

done

