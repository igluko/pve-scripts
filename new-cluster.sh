#!/bin/bash

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

function apt-install {
    if ! which "$1" >/dev/null
    then
        apt update -y || true
        apt install -y "$1"
    fi
}

#-----------------------START-----------------------#

# Setup SSH
DST_IP="localhost"
DST_USER="root"
DST="${DST_USER}@${DST_IP}"
SSH="ssh -C -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q ${DST}"

# Install soft
printf "\n${GREEN}apt install fio jq fdisk nvme-cli${NC}\n"
apt-install nvme-cli

# Загружаем переменные из файла
load "${SCRIPTPATH}/.env"

# Шаг 2 - firewall
printf "\n${ORANGE}Шаг 2 - firewall${NC}\n"

FILE="/etc/pve/firewall/cluster.fw"
if !  [[ -f ${FILE} ]]
then
    mkdir -p /etc/pve/firewall
    printf "[OPTIONS]\n\nenable: 0\n\n[RULES]\n\n" >> ${FILE}
fi

echo "TXT:whitelist.g00.link:"
DOMAIN_LIST=$(dig whitelist.g00.link +short -t TXT | xargs)
for DOMAIN in $DOMAIN_LIST
do
    echo " ${DOMAIN}"
    IP_LIST=$(dig ${DOMAIN} +short)
    for IP in $IP_LIST
    do
        echo " - ${IP}"
        if ! grep ${IP} ${FILE}
        then
            echo "IN ACCEPT -source ${IP} -log nolog # ${DOMAIN}" >> ${FILE}
        fi
    done
done

# Откладываем выключение firewall на случай аварии
nohup sleep 300 >/dev/null 2>&1 && pve-firewall stop &
PID=$!
printf "\n${RED}Откладываем выключение firewall на 5 минут, PID=${PID}${NC}\n"

# Выключаем firewall
sed -i 's/enable: 0/enable: 1/g' ${FILE}
printf "Firewall activated. Please check connect to ${GREEN}https://$(hostname -I | xargs):8006${NC}\n"
read -e -p "> " -i "ok"

# Отменяем отложенное отключение firewall
echo "Отменяем отложенное отключение firewall"
kill ${PID} || true
# Запускаем firewall
pve-firewall start

# Шаг 3 - документация
printf "\n${ORANGE}Шаг 3 - документация${NC}\n"

# IP
${SSH} "ip addr"
# Mother
${SSH} "cat /sys/devices/virtual/dmi/id/{board_vendor,board_name,board_version,bios_version,bios_date} 2>/dev/null ; true"
# RAM
${SSH} "dmidecode -t memory | grep Speed | head -2 | xargs -r"
# NVME
if ${SSH} "ls /dev/nvme*n1 2>&1 >/dev/null"
then
    ${SSH} "cat /sys/class/block/nvme*/device/{model,serial,firmware_rev} 2>/dev/null ; true"
    ${SSH} "fdisk -l /dev/nvme*n1 2>/dev/null | grep size"
    ${SSH} "nvme list"
    ${SSH} "ls /dev/nvme*n1 | xargs -n1 nvme id-ns -H | (grep 'LBA Format')"

    printf "\nphysical_block_size\nhw_sector_size\nminimum_io_size\n-\n"
    ${SSH} "cat /sys/block/nvme*n1/queue/physical_block_size; echo '-'"
    ${SSH} "cat /sys/block/nvme*n1/queue/hw_sector_size; echo '-'"
    ${SSH} "cat /sys/block/nvme*n1/queue/minimum_io_size; echo '-'"
fi

printf "\n${RED}Please update Documentation${NC}\n"
read -e -p "> " -i "ok"

# Шаг 4 - hosts
printf "\n${ORANGE}Шаг 4 - hosts${NC}\n"
echo "1-я нода не нуждается в обновлении файла hosts"

# Шаг 5 - Отображать имя хоста во вкладке
printf "\n${ORANGE}Шаг 5 - Отображать имя хоста во вкладке${NC}\n"
FILE=".bashrc"
if ! grep "If this is an xterm set the title to host:dir" ${FILE}
then
    cat "${SCRIPTPATH}/${FILE}" >> ~/"${FILE}"
fi

# Шаг 7 - Лицензии и обновления
printf "\n${ORANGE}Шаг 7 - Лицензии и обновления${NC}\n"

if pvesubscription get | tee /dev/tty | grep -q notfound
then
    # Бесконечный цикл
    while true; do
    # Set the text color to red
    tput setaf 1
    # Спрашиваем у пользователя, повторить команду или выйти из цикла
    read -p "Do you wanna set licence? (Y/n)? " ANSWER
    # Set the text color back to the default
    tput sgr0

    # Если пользователь выбрал выйти из цикла, выходим
    if [ "$ANSWER" == "n" ]; then
        break
    fi
    echo "Please enter PVE Licence"
    read -e -p "> " -i "" LICENSE
    # Проверяем успешность выполнения команды
    if pvesubscription set ${LICENSE}; then
        # Если команда выполнилась успешно, выходим из цикла
        break
    fi
    done
fi

#  Меняем RU репозитории на обычные, RU еле шевелятся:
$SSH "sed -i s/\.ru\./\./ /etc/apt/sources.list"

# В заключении обновляем пакеты на сервере:
$SSH "apt update ; apt dist-upgrade -y"

# Включаем новые возможности zfs, если таковые есть
$SSH "zpool upgrade rpool"

# Шаг 9 - Шифрование данных кластера
printf "\n${ORANGE}Шаг 9 - Шифрование данных кластера${NC}\n"

if ${SSH} "zfs get encryption -p -H rpool/data -o value | grep -q off"
then
    # Задаем пароль шифрования ZFS
    PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20 ; echo '')
    printf "\n${RED}Пароль шифрования ZFS:${NC}\n"
    read -e -p "> " -i "${PASSWORD}" PASSWORD

    # Создадим файл с ключом шифрования в папке /tmp
    FILE="/tmp/passphrase"
    ${SSH} "echo ${PASSWORD} > ${FILE}"
    
    # Шифруем rpool/data
    ${SSH} "zfs destroy rpool/data; true"
    ${SSH} "zfs create -o encryption=on -o keyformat=passphrase -o keylocation=file:///tmp/passphrase rpool/data"
fi
# Проверяем результат
run "zfs list -o name,encryption,keylocation,encryptionroot,keystatus"

# Шаг 8 - Настройка ZFS
printf "\n${ORANGE}Шаг 8 - Настройка ZFS${NC}\n"
${SSH} "zpool set autotrim=on rpool"
${SSH} "zfs set atime=off rpool"
${SSH} "zfs set compression=zstd-fast rpool"
${SSH} "pvesm set local-zfs --blocksize 16k"
${SSH} "echo 10779361280 >> /sys/module/zfs/parameters/zfs_arc_sys_free"

FILE="/etc/modprobe.d/zfs.conf"
TEXT="options zfs zfs_arc_sys_free=10779361280"

if ! $SSH "grep \"${TEXT}\" ${FILE}" 2>&1 >/dev/null
then
    ${SSH} "echo \"${TEXT}\" > ${FILE}"
    ${SSH} "update-initramfs -u"
fi

# Проверяем результат   
run "zpool list -o name,autotrim" 
run "zfs list -o name,atime,compression"

# ${SSH} "zfs set primarycache=metadata rpool"

# Шаг X - Download virtio-win.iso
printf "\n${ORANGE}Шаг X - Download virtio-win.iso${NC}\n"
WGET="wget -N --progress=bar:force --content-disposition --directory-prefix=/var/lib/vz/template/iso/"
# Latest:
${SSH}  "${WGET} https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
# Latest for windows 7:
${SSH}  "${WGET} https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.173-9/virtio-win-0.1.173.iso"

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



# # check step
# if ! $SSH "[[ -d /etc/pve ]]"
# then
#     1-step
# else
#     2-step
# fi

