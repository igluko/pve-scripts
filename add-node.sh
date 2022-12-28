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
    if [[ $# -eq 2 ]]
    then
        local FILE="${2}"
    else
        local FILE="${SCRIPTPATH}/.env"
    fi

    load ${FILE}

    if [[ ! -v ${VARIABLE} ]];
    then
        eval ${VARIABLE}=""
    fi
    local VALUE="$(echo ${!1} | xargs)"

    printf "\n${RED}Please input ${VARIABLE}${NC}\n"
    read -e -p "> " -i "${VALUE}" ${VARIABLE}
    save ${VARIABLE} ${FILE}
    # echo "$VARIABLE is $VALUE"
}

function apt-install {
    for NAME in $*
    do
        local DPKG="dpkg -l | awk '\$2==\"${NAME}\" && \$1==\"ii\" {print \$1,\$2,\$3}'"
        if ! ${SSH} "${DPKG} | grep -q ii"
        then
            ${SSH} -t "apt update -y || true"
            ${SSH} -t "apt install -y ${NAME}"
        fi
        # Проверяем результат
        ${SSH} -t "${DPKG}"
    done
}

function Q {
    while true
    do
        printf "\n${RED}$* ${NC}(n\y)\n"
        read -p "> " ANSWER
        [[ "$ANSWER" == "y" ]] && return 0
        [[ "$ANSWER" == "n" ]] && return 1
    done
}

# Функция для вставки строки в файл, если до этого его там не было
# Функция заменит строку в файле, если совпадет MATCH условие
function insert-ssh {
    FILE="${1}"
    REPLACE="${2}"

    ${SSH} "touch ${FILE}"

    if [[ $# -eq 2 ]]
    then
        MATCH="$2"
    else
        MATCH="$3"
    fi

    if ! ${SSH} "grep -q \"${REPLACE}\" ${FILE}"
    then
        ${SSH} "echo \"${REPLACE}\" >> ${FILE}"
    else
        ESCAPED_REPLACE=$(printf '%s\n' "$REPLACE" | sed -e 's/[\/&]/\\&/g')
        ESCAPED_MATCH=$(printf '%s\n' "$MATCH" | sed -e 's/[\/&]/\\&/g')
        ${SSH} "sed -i '/${ESCAPED_MATCH}/ s/.*/${ESCAPED_REPLACE}/' ${FILE}"
    fi
}

function insert {
    FILE="${1}"
    REPLACE="${2}"

    eval "touch ${FILE}"

    if [[ $# -eq 2 ]]
    then
        MATCH="$2"
    else
        MATCH="$3"
    fi

    if ! eval "grep -q \"${REPLACE}\" ${FILE}"
    then
        eval "echo \"${REPLACE}\" >> ${FILE}"
    else
        ESCAPED_REPLACE=$(printf '%s\n' "$REPLACE" | sed -e 's/[\/&]/\\&/g')
        ESCAPED_MATCH=$(printf '%s\n' "$MATCH" | sed -e 's/[\/&]/\\&/g')
        eval "sed -i '/${ESCAPED_MATCH}/ s/.*/${ESCAPED_REPLACE}/' ${FILE}"
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

    # Add public key form authorized_keys.g00.link
    printf "\n${ORANGE}Add public key from authorized_keys.g00.link${NC}\n"
    IFS=$'\n\t'
    TXT_LIST=$(dig authorized_keys.g00.link +short -t TXT | sed 's/" "//g'| xargs -n1)

    for TXT in ${TXT_LIST}
    do
        IFS=$' \n\t'
        insert-ssh "/root/.ssh/authorized_keys" "$TXT"
    done

    # Install soft
    printf "\n${ORANGE}apt install${NC}\n"
    apt-install git jq nvme-cli patch sanoid

    # Шаг 2 - firewall
    printf "\n${ORANGE}Шаг 2 - firewall${NC}\n"

    FILE="/etc/pve/firewall/cluster.fw"
    # сохраняем Hostname для использования в Firewall 
    DOMAIN_LOCAL=$(hostname -f)
    DOMAIN_REMOTE=$(${SSH} hostname -f)
    # сохраняем IP целевого сервера и IP ssh клиента для сравнения
    IP_LOCAL=$(hostname -i)
    IP_REMOTE=$($SSH hostname -i)

    # Если firewall на целевом сервере не существует
    if ! ${SSH} [[ -f ${FILE} ]]
    then
        ${SSH} "mkdir -p /etc/pve/firewall"
        # Create empty disabled firewall
        if ! ${SSH} "[[ -f ${FILE} ]]"
        then
            ${SSH} "mkdir -p /etc/pve/firewall"
            ${SSH} "printf '[OPTIONS]\n\nenable: 0\n\n[RULES]\n\n' >> ${FILE}"
        fi
    fi

    # Если firewall на SSH клиенте существует и целевой сервер не localhost
    if [[ -f ${FILE} ]] && [[ ${IP_LOCAL} != ${IP_REMOTE} ]]
    then
        # Если Firerwall на SSH клиенте не содержит IP целевого сервера
        if ! grep -q ${IP_REMOTE} ${FILE}
        then
            if Q "Добавить IP адрес удаленного сервера в Firewall локального сервера?"
            then
                # Add target IP IP to local Firewall
                MATCH="${${IP_REMOTE}}"
                REPLACE="IN ACCEPT -source ${IP_REMOTE} -log nolog # ${DOMAIN_REMOTE}"
                insert "${FILE}" "${REPLACE}" "${MATCH}"
            fi
        fi
        if Q "Скопировать Firewall локального сервера на удаленный сервер?"
        then
            cat ${FILE} | ${SSH} "cat > ${FILE}"
        fi
    fi
    
    # Add whitelist.g00.link to target host Firewall
    printf "\n${GREEN}GET TXT:whitelist.g00.link${NC}\n"

    DOMAIN_LIST=$(dig whitelist.g00.link +short -t TXT | xargs)
    for DOMAIN in $DOMAIN_LIST
    do
        echo " ${DOMAIN}"
        IP_LIST=$(dig ${DOMAIN} +short)
        for IP in $IP_LIST
        do
            echo " - ${IP}"
            # Add IP to target host Firewall
            MATCH="${IP}"
            REPLACE="IN ACCEPT -source ${IP} -log nolog # ${DOMAIN}"
            insert-ssh "${FILE}" "${REPLACE}" "${MATCH}"
        done
    done

    # Add IP_LOCAL to target host Firewall
    REPLACE="IN ACCEPT -source ${IP_LOCAL} -log nolog # ${DOMAIN_LOCAL}"
    MATCH="${IP_LOCAL}"
    insert-ssh "${FILE}" "${REPLACE}" "${MATCH}"

    # Проверяем результат
    run "cat ${FILE}"

    # Если firewall отключен, включаем его
    if ${SSH} "grep -q \"enable: 0\"  ${FILE}"
    then
        # # Откладываем выключение firewall на случай аварии
        # ${SSH} "sleep 30 && pve-firewall stop &"
        # exit
        # # printf "\n${RED}Откладываем выключение firewall на 5 минут, PID=${PID}${NC}\n"

        # Включаем firewall
        sed -i 's/enable: 0/enable: 1/g' ${FILE}
        printf "\nFirewall activated. Please check connect to ${GREEN}https://$(hostname -I | xargs):8006${NC}\n"
        read -e -p "> " -i "ok"

        # # Отменяем отложенное отключение firewall
        # echo "Отменяем отложенное отключение firewall"
        # kill ${PID} || true
        # Запускаем firewall
        # pve-firewall start
    fi

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
    echo "Пропущено"
    # local FILE="/etc/hosts"
    # if ! grep ${DST_IP} ${FILE}
    # then
    #     echo "${DST_IP} ${DST_HOSTNAME}.local ${DST_HOSTNAME}" >> ${FILE}
    # fi

    # cat ${FILE} | ${SSH} "cat > ${FILE}"

    # Шаг 5 - Отображать имя хоста во вкладке
    printf "\n${ORANGE}Шаг 5 - Отображать имя хоста во вкладке${NC}\n"
    local FILE=".bashrc"
    if ! $SSH "grep \"If this is an xterm set the title to host:dir\" ${FILE}"
    then
        cat "${SCRIPTPATH}/${FILE}" | ${SSH} "cat >> ${FILE}"
    fi

    # Шаг 6 - Download virtio-win.iso
    printf "\n${ORANGE}Шаг 6 - Download virtio-win.iso${NC}\n"
    WGET="wget -N --progress=bar:force --content-disposition --directory-prefix=/var/lib/vz/template/iso/"
    # Latest:
    ${SSH} -t "${WGET} https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
    # Latest for windows 7:
    ${SSH} -t "${WGET} https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.173-9/virtio-win-0.1.173.iso"
    # Проверяем результат
    run "pvesm list local"

    # Шаг 7 - Лицензии и обновления
    printf "\n${ORANGE}Шаг 7 - Лицензии и обновления${NC}\n"

    if ${SSH} -t "pvesubscription get | tee /dev/tty | grep -q notfound"
    then
        # Бесконечный цикл
        while true
        do
            # Спрашиваем у пользователя, повторить команду или выйти из цикла
            if Q "Do you wanna set licence?"
            then
                echo "Please enter PVE Licence"
                read -e -p "> " -i "" LICENSE
                # Проверяем успешность выполнения команды
                if pvesubscription set ${LICENSE}
                then
                    # Если пользователь выбрал n, выходим из цикла
                    break
                fi
            else
                break
            fi
        done
    fi

    #  Меняем RU репозитории на обычные, RU еле шевелятся:
    $SSH "sed -i s/\.ru\./\./ /etc/apt/sources.list"

    # Обносляем пакеты на сервере?
    if Q "Обновляем пакеты?"
        then
        $SSH "apt update; apt dist-upgrade -y"
        if Q "Включаем новые возможности ZFS? (zpool upgrade)"
            then
            # Включаем новые возможности zfs, если таковые есть
            $SSH "zpool upgrade rpool"
        fi
    fi

   # Шаг 9 - Шифрование данных кластера
    printf "\n${ORANGE}Шаг 9 - Шифрование данных кластера${NC}\n"

    if ${SSH} "zfs get encryption -p -H rpool/data -o value | grep -q off"
    then
        FILE="/tmp/passphrase"
        # Задаем пароль шифрования ZFS
        if [[ -f $FILE ]]
        then
            PASSWORD=$(cat $FILE)
            echo "Предложен пароль из файла $FILE с локального сервера"
        else
            PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20 ; echo '')
        fi
        
        printf "\n${RED}Пароль шифрования ZFS:${NC}\n"
        read -e -p "> " -i "${PASSWORD}" PASSWORD

        # Создадим файл с ключом шифрования в папке /tmp
        ${SSH} "echo ${PASSWORD} > ${FILE}"
        
        # Шифруем rpool/data
        ${SSH} "zfs destroy rpool/data; true"
        ${SSH} "zfs create -o encryption=on -o keyformat=passphrase -o keylocation=file:///tmp/passphrase rpool/data"
    fi
    # Проверяем результат
    run "zfs list -o name,encryption,keylocation,encryptionroot,keystatus"

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

     
    # Шаг 10 - доверие между узлами
    printf "\n${ORANGE}Шаг 10 - доверие между узлами${NC}\n"
    echo "Пропущен"

    # Шаг 11 - добавление ноды в кластер
    printf "\n${ORANGE}Шаг 11 - добавление ноды в кластер${NC}\n"

    # Если на удаленной ноде нет кластера
    if ! $SSH "pvecm status" 2>&1 >/dev/null
    then
        # Проверка параметров
        run "hostname"
        run "hostname -f"
        run "hostname -i"

        # Если на локальной ноде есть кластер, предлагаем добавить удаленную ноду в него
        if eval "pvecm status" 2>&1 >/dev/null && Q "Добавить ноду в существующий кластер"
        then
                # echo "Please take snapshot on ALL nodes, and add node to cluster"
                # read -e -p "> " -i "ok"
                # #$SSH "zfs snapshot -r rpool@before_cluster-${date +%s}"
                # pvecm add IP_ADDRESS_OF_EXISTING_NODE
                echo "Не реализовано"
        elif Q "Создать новый кластер?"
        then
            # Создание защитных снимков
            printf "\n${RED}Создание защитного снимка rpool/ROOT@before_cluster-$(date +%s)${NC}\n"
            $SSH "zfs snapshot -r rpool/ROOT@before_cluster-$(date +%s)"
            printf "\n${RED}Enter cluster name ${NC}\n"
            read -p "> " ANSWER
            run "pvecm create ${ANSWER}"
        fi
        # Проверяем результат
        # run "pvecm status"
    fi

    # Шаг 12 - Настройка Syncthing
    printf "\n${ORANGE}Шаг 8 - Настройка Syncthing${NC}\n"
    # Установка
    if ! ${SSH} "which syncthing >/dev/null"
    then
        ${SSH} "curl -s -o /usr/share/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg"
        ${SSH} "echo \"deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable\" | tee /etc/apt/sources.list.d/syncthing.list"
        ${SSH} "printf \"Package: *\nPin: origin apt.syncthing.net\nPin-Priority: 990\n\" | tee /etc/apt/preferences.d/syncthing"
        ${SSH} "apt update -y || true"
        ${SSH} "apt install -y syncthing"
        ${SSH} "systemctl enable syncthing@root"
        ${SSH} "systemctl start syncthing@root"
    fi
    # Проверяем результат
    ${SSH} -t "systemctl status --no-pager syncthing@root"

    # Добавляем папки
    FOLDER_NAME="iso"
    FOLDER_PATH="/var/lib/vz/template/iso"
    if ! ${SSH} "syncthing cli config folders list | grep -q ${FOLDER_NAME}"
    then
        ${SSH} "syncthing cli config folders add --id ${FOLDER_NAME} --path ${FOLDER_PATH}"
    fi

    # Настройка
    if Q "Объединить локальную и удаленную ноды Syncthing?"
    then
        # add local device to remote Syncthing
        ID1=$(syncthing --device-id)
        ${SSH} "syncthing cli config devices add --device-id ${ID1}"
        ${SSH} "syncthing cli config devices ${ID1} auto-accept-folders set true"
        ${SSH} "syncthing cli config devices ${ID1} introducer set true"
        # add remote device to local Syncthing
        ID2=$(${SSH} syncthing --device-id)
        eval "syncthing cli config devices add --device-id ${ID2}"
        eval "syncthing cli config devices ${ID2} auto-accept-folders set true"
        eval "syncthing cli config devices ${ID2} introducer set true"
        
        # add local folders to remote
        for FOLDER in $(syncthing cli config folders list)
        do
            eval "syncthing cli config folders ${FOLDER} devices add --device-id ${ID2}"
        done
        # Проверка
        printf "\n${ORANGE}local devices list:${NC}\n"
        eval "syncthing cli config devices list"
        printf "\n${ORANGE}remote devices list:${NC}\n"
        ${SSH} "syncthing cli config devices list"
        printf "\n${ORANGE}local folder list:${NC}\n"
        eval "syncthing cli config folders list"
        printf "\n${ORANGE}remote folder list:${NC}\n"
        ${SSH} "syncthing cli config folders list"
    fi

    # Активируем shared режим для local storage
    ${SSH} pvesm set local --shared 1

    # Шаг 12.1 - Копирование /etc/environment
    printf "\n${ORANGE}Шаг 12.1 - Копирование /etc/environment${NC}\n"

    if ! Q "Скопировать /etc/environment на удаленный хост?"
    FILE="/etc/environment"
    then
        cat ${FILE} | ${SSH} "cat > ${FILE}"
    fi

    # Шаг 13 - Проверка наличия скриптов
    printf "\n${ORANGE}Шаг 13 - Проверка наличия скриптов${NC}\n"

    if ! ${SSH} [[ -e /root/Sync/pve-scripts ]]
    then
        # ${SSH} "cd /root/Sync && git clone git@github.com:igluko/pve-scripts.git"
        ${SSH} -t "cd /root/Sync && git clone https://github.com/igluko/pve-scripts.git"
    else
        # ${SSH} "cd /root/Sync && git pull git@github.com:igluko/pve-scripts.git"
        ${SSH} -t "cd /root/Sync/pve-scripts && git pull https://github.com/igluko/pve-scripts.git"
    fi

    # Шаг 13.1 - Патч Proxmox для работы с шифрованным ZFS и pve-zsync
    printf "\n${ORANGE}Шаг 13.1 - Патч Proxmox для работы с шифрованным ZFS и pve-zsync${NC}\n"
    FILE="/usr/share/perl5/PVE/Storage/ZFSPoolPlugin.pm"
    PATCH="/root/Sync/pve-scripts/ZFSPoolPlugin.pm.patch"
    ! ${SSH} -t "patch --forward ${FILE} ${PATCH} 2>&1  | tee /dev/tty | grep -q failed"

    # Шаг 14 - pve-autorepl
    printf "\n${ORANGE}Шаг 14 - pve-autorepl${NC}\n"
    echo "Пропустили"

    # Шаг 15 - meminfo
    printf "\n${ORANGE}Шаг 15 - meminfo${NC}\n"
    ${SSH} "/root/Sync/pve-scripts/notes.sh --add_cron"

    # Шаг 15.1 - ROOT reservation
    printf "\n${ORANGE}Шаг 15.1 - ROOT reservation${NC}\n"
    ${SSH} -t "/root/Sync/pve-scripts/zfs-autoreservation.sh rpool/ROOT 5368709120"

    # Шаг 16 - swap через zRam
    printf "\n${ORANGE}Шаг 16 - swap через zRam${NC}\n"
    echo "Пропустили"

    # Шаг 17 - ebtables
    printf "\n${ORANGE}Шаг 17 - ebtables${NC}\n"
    ${SSH} "ip link"
    printf "\n${ORANGE}---${NC}\n"
    ${SSH} -t "/root/Sync/pve-scripts/ebtables.sh"

    # Шаг 18 - bridge и vlan
    printf "\n${ORANGE}Шаг 18 - bridge и vlan${NC}\n"
    echo "Пропустили"

    # Шаг 18.1 - Добавление новых Bridge
    printf "\n${ORANGE}Шаг 18.1 - Добавление новых Bridge${NC}\n"
    echo "Пропустили"

    # Шаг 19 - Zabbix
    printf "\n${ORANGE}Шаг 19 - Zabbix${NC}\n"
    echo "Пропустили"

    # Шаг 20 - Бекап /etc
    printf "\n${ORANGE}Шаг 20 - Бекап /etc${NC}\n"
    while true
    do
        if ! Q "Настроить бэкап etc на PBS?"
        then
            break
        fi

        # Обновляем доступы
        FILE=/etc/environment
        update PBS_PASSWORD ${FILE}
        update PBS_REPOSITORY ${FILE}

        # Добавляем IP адрес в Firewall PBS
        # echo "backup@pbs@162.55.131.125:Vinsent" | sed -E 's/(.*@)(.*)(:.*)/\2/'

        # Пробуем запустить скрипт
        if ${SSH} -t "/root/Sync/pve-scripts/etc_backup.sh"
        then
            break
        fi
    done

    # Шаг 21 - Проверка актуальности беков PBS
    printf "\n${ORANGE}Шаг 21 - Проверка актуальности беков PBS${NC}\n"
    while true
    do
        if ! Q "Настроить проверку актуальности беков PBS?"
        then
            break
        fi

        # Обновляем доступы
        FILE=/etc/environment
        update TG_TOKEN ${FILE}
        update TG_CHAT ${FILE}

        # Пробуем запустить скрипт
        if ${SSH} -t "/root/Sync/pve-scripts/backup-check.py"
        then
            # Добавляем скрипт в крон и выходим
            ${SSH} "/root/Sync/pve-scripts/backup-check.py -add_cron" 
            break
        fi
    done

    # Шаг 23 - Sanoid
    printf "\n${ORANGE}Шаг 23 - Sanoid${NC}\n"

    if Q "Настроить переодические снимки через Sanoid?"
    then
        # Устанавливаем
        apt-install sanoid
        # Меняем часовой пояс
        ${SSH} "sed -i -E '/Environment=TZ=/ s/UTC/Europe\/Moscow/' /lib/systemd/system/sanoid.service"
        # Конфигурирование sanoid:
        ${SSH} "mkdir -p /etc/sanoid"
        cat ${SCRIPTPATH}/sanoid.conf | ${SSH} "cat > /etc/sanoid/sanoid.conf"
        # Перечитываем конфиги сервисов
        ${SSH} "systemctl daemon-reload"
        # Проверка сервисов
        ${SSH} -t "systemctl status --no-pager sanoid.timer"
    fi

    # Шаг 24 - Проверка снимков syncoid
    printf "\n${ORANGE}Шаг 24 - Проверка снимков syncoid${NC}\n"

    while true
    do
        if ! Q "Настроить проверку снимков syncoid?"
        then
            break
        fi

        # Обновляем доступы
        FILE=/etc/environment
        update TG_TOKEN ${FILE}
        update TG_CHAT ${FILE}

        # Пробуем запустить скрипт
        if ${SSH} -t "/root/Sync/pve-scripts/sync-check.sh 1"
        then
            break
        fi
    done
}

#-----------------------START-----------------------#

# Check terminal
if ! [[ -t 1 ]]
then
    echo "This script must be running in interactive mode"
    exit 1
fi

# Setup SSH
# -A option enables forwarding of the authentication agent connection.
update "DST_IP"
DST_USER="root"
DST="${DST_USER}@${DST_IP}"
SSH="ssh -C -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q ${DST}"

# Copy public key to authorized_keys
if ! ${SSH} "true"
then
    echo
    FILE='/root/.ssh/id_rsa.pub'
    if [ -f ${FILE} ]; then
        ssh-copy-id -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${DST}
        # fix for ssh with key forwarding
        ssh-copy-id -i ${FILE} -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${DST}
    else
        echo "${FILE} not exist"
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