#!/bin/bash

###
# This script prepares a new PVE node
# Tested on Hetzner AX-101 servers
###

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
# load functions
source $SCRIPT_PATH/FUNCTIONS

# read envivoments
source  /etc/environment

function SSH {
    # Set global variable for the first time
    if [[ ! -v SSH_USER ]]
    then
        SSH_USER="root"
    fi
    # Set global variable and save it to the file for the first time
    if [[ ! -v SSH_IP ]]
    then
        UPDATE "SSH_IP" "${SCRIPT_PATH}/.env"
        # Try to connect, if it fails, then copy the public key
        if ! SSH "true"
        then
            FILE='/root/.ssh/id_rsa.pub'
            if [[ -f ${FILE} ]]
            then
                ssh-copy-id -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP}
                # fix for ssh with key forwarding
                ssh-copy-id -i ${FILE} -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP}
            else
                echo "${FILE} not exist"
                exit 1
            fi
        fi
    fi
    # -A option enables forwarding of the authentication agent connection.
    local SSH_OPT=(-C -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q)
    
    # Add another SSH options if variable SSH_OPT_ADD is set
    if [[ -v SSH_OPT_ADD ]]
    then
        local SSH_OPT+=(${SSH_OPT_ADD[@]})
    fi
    
    # Bash quoted array expansion for input args
    # https://stackoverflow.com/questions/12985178/bash-quoted-array-expansion
    # ARGS=$(printf " %q" "$@")

    # Load local functions into a remote session before doing work
    local COMMAND="$(typeset -f INSTALL INSERT); $@"

    ssh "${SSH_OPT[@]}" ${SSH_USER}@${SSH_IP} "${COMMAND}"
}

function SSH_T {
    local SSH_OPT_ADD=(-t)
    SSH "$@"
}

function SSH_H2 {
    printf "\n${GREEN}$@${NC}\n"
    SSH "$@"
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
        local FILE="${SCRIPT_PATH}/.env"
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

function ACTIVATE_RESCUE {
    # 0 BIOS
    Q "Please check BIOS"

    # 1 ISO
    Q "Please activate RescueCD in Hetzner Robot panel and Execute an automatic hardware reset"
}

function PVE_INSTALL {
    # Install soft
    printf "\n${ORANGE}apt install${NC}\n"
    INSTALL nvme-cli

    # Show node info
    printf "\n${GREEN}hostnamectl${NC}\n"
    SSH "hostnamectl"

    # Show nvme
    printf "\n${GREEN}nvme-list${NC}\n"
    SSH "nvme list"

    if Q "Format nvme disks?"
    then
        SSH "nvme format /dev/nvme0n1"
        SSH "nvme format /dev/nvme1n1"
    fi

    # Show ip
    printf "\n${GREEN}ip addr${NC}\n"
    SSH "ip addr | grep -E 'altname|inet '"
    printf "\n${GREEN}ip route${NC}\n"
    SSH "ip route | grep default"

    Q "Starting to install PVE" || exit

    # ISO="proxmox-ve_7.3-1.iso"
    # eval SSH "wget -N http://download.proxmox.com/iso/$ISO"
    URL=$(curl -s https://www.proxmox.com/en/downloads/category/iso-images-pve | grep -o "/en/downloads?.*" | head -n1 | sed 's/".*//')
    WGET="wget -q --show-progress -N --progress=bar:force --content-disposition"
    SSH "${WGET} 'https://www.proxmox.com$URL'"
    ISO=$(${SSH[@]} "ls proxmox*")

    # generate random password
    VNC_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo '')
    printf "${ORANGE} VNC Password is ${GREEN}${VNC_PASSWORD}${NC}\n"

    # Start KVM
    eval SSH "pkill qemu-system-x86 || true"
    printf "${RED} Please open VNC console to ${SSH_IP}, install PVE and press Next${NC}\n"
    SSH "printf \"change vnc password\n%s\n\" ${VNC_PASSWORD} | qemu-system-x86_64 -enable-kvm -smp 4 -m 4096 -boot once=d -cdrom ./$ISO -drive file=/dev/nvme0n1,format=raw,cache=none,index=0,media=disk -drive file=/dev/nvme1n1,format=raw,cache=none,index=1,media=disk -vnc 0.0.0.0:0,password -monitor stdio" >/dev/null &
   
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



    SSH "sed -i -E \"s/iface ens3 inet manual/iface ${IF_NAME} inet manual/\" ${INTERFACES}"
    SSH "sed -i -E \"s/bridge-ports .*/bridge-ports ${IF_NAME}/\"  ${INTERFACES}" 
    SSH "sed -i -E \"s/address .*/address ${IP}\/32/\" ${INTERFACES}"
    SSH "sed -i -E \"s/gateway .*/gateway ${GATEWAI}/\"  ${INTERFACES}"

    SSH "zfs set mountpoint=/ rpool/ROOT/pve-1"
    SSH "zpool export rpool"

    SSH "reboot" 2>/dev/null | true
    printf "${GREEN}"
    echo "Proxmox will be enabled at this link in 2 minutes"
    printf "${NC}"
    printf '\e]8;;https://'${SSH_IP}':8006\e\\https://'${SSH_IP}':8006\e]8;;\e\\\n' 
}

function 0_ADD_PUBLIC_KEYS {
    H1
    echo "Add public keys from authorized_keys.g00.link"

    TXT_LIST=$(dig authorized_keys.g00.link +short -t TXT | sed 's/" "//g'| xargs -n1)
    for TXT in ${TXT_LIST}
    do
        SSH "INSERT /root/.ssh/authorized_keys '${TXT}'"
    done
}

function 0_INSTALL_SOFTWARE {
    H1
    SSH "INSTALL git jq nvme-cli patch sanoid"
}

function 2_FIREWALL {
    H1
    local FILE="/etc/pve/firewall/cluster.fw"
    # сохраняем Hostname для использования в Firewall 
    local DOMAIN_LOCAL=$(hostname -f)
    local DOMAIN_REMOTE=$(SSH "hostname -f")
    # сохраняем IP целевого сервера и IP ssh клиента для сравнения
    local IP_LOCAL=$(hostname -i)
    local IP_REMOTE=$(SSH "hostname -i")

    # Если firewall на целевом сервере не существует
    if ! SSH "[[ -f ${FILE} ]]"
    then
        SSH "mkdir -p /etc/pve/firewall"
        SSH "printf '[OPTIONS]\n\nenable: 0\n\n[RULES]\n\n' >> '${FILE}'"
    fi

    # Если firewall на SSH клиенте существует и целевой сервер не localhost
    if [[ -f ${FILE} ]] && [[ ${IP_LOCAL} != ${IP_REMOTE} ]]
    then
        # Если Firerwall на SSH клиенте не содержит IP целевого сервера
        if ! grep -q ${IP_REMOTE} ${FILE}
        then
            if Q "Добавить IP адрес удаленного сервера в Firewall локального сервера?"
            then
                # Add target IP to local Firewall
                MATCH="${IP_REMOTE}"
                REPLACE="IN ACCEPT -source ${IP_REMOTE} -log nolog # ${DOMAIN_REMOTE}"
                INSERT "${FILE}" "${REPLACE}" "${MATCH}"
            fi
        fi
        if Q "Скопировать Firewall локального сервера на удаленный сервер?"
        then
            cat ${FILE} | SSH "cat > '${FILE}'"
        fi
    fi
    
    # Add whitelist.g00.link to target host Firewall
    H2 "GET TXT:whitelist.g00.link"

    DOMAIN_LIST=$(dig whitelist.g00.link +short -t TXT | xargs | tr " " "\n")
    for DOMAIN in ${DOMAIN_LIST}
    do
        echo " ${DOMAIN}"
        IP_LIST=$(dig ${DOMAIN} +short)
        for IP in $IP_LIST
        do
            echo " - ${IP}"
            # Add IP to target host Firewall
            MATCH="${IP}"
            REPLACE="IN ACCEPT -source ${IP} -log nolog # ${DOMAIN}"
            SSH "INSERT '${FILE}' '${REPLACE}' '${MATCH}'"
        done
    done

    # Add IP_LOCAL to target host Firewall
    H2 "Add IP_LOCAL ${IP_LOCAL} to target host Firewall"

    REPLACE="IN ACCEPT -source ${IP_LOCAL} -log nolog # ${DOMAIN_LOCAL}"
    MATCH="${IP_LOCAL}"
    SSH "INSERT '${FILE}' '${REPLACE}' '${MATCH}'"

    # Проверяем результат
    SSH_H2 "cat ${FILE}"

    # Если firewall отключен, включаем его
    if SSH "grep -q \"enable: 0\"  ${FILE}"
    then
        # # Откладываем выключение firewall на случай аварии
        # SSH "sleep 30 && pve-firewall stop &"
        # exit
        # # printf "\n${RED}Откладываем выключение firewall на 5 минут, PID=${PID}${NC}\n"

        # Включаем firewall
        SSH "sed -i 's/enable: 0/enable: 1/g' ${FILE}"
        printf "\nFirewall activated. Please check connect to ${GREEN}https://$(hostname -i | xargs):8006${NC}\n"
        read -e -p "> " -i "ok"

        # # Отменяем отложенное отключение firewall
        # echo "Отменяем отложенное отключение firewall"
        # kill ${PID} || true
        # Запускаем firewall
        # pve-firewall start
    fi
}

function 3_DOCUMENTATION {
    H1
    # IP
    SSH "ip addr"
    # Mother
    SSH "cat /sys/devices/virtual/dmi/id/{board_vendor,board_name,board_version,bios_version,bios_date} 2>/dev/null ; true"
    # RAM
    SSH "dmidecode -t memory | grep Speed | head -2 | xargs -r"
    # NVME
    SSH "nvme list"

    Q "Please update Documentation"
}

function 4_HOSTS {
    H1
    echo "Пропущено"
    # local FILE="/etc/hosts"
    # if ! grep ${SSH_IP} ${FILE}
    # then
    #     echo "${SSH_IP} ${DST_HOSTNAME}.local ${DST_HOSTNAME}" >> ${FILE}
    # fi

    # cat ${FILE} | SSH "cat > ${FILE}"
}

function 5_TAB_NAME {
    H1
    echo "Настройка отображения имени хоста во вкладке терминала"
    local FILE=".bashrc"
    if ! SSH "grep -q 'If this is an xterm set the title to host:dir' '${FILE}'"
    then
        cat "${SCRIPT_PATH}/${FILE}" | SSH "cat >> '${FILE}'"
    fi
}

function 12_SYNCTHING {
    H1
    # Установка
    if ! SSH "which syncthing >/dev/null"
    then
        SSH "curl -s -o /usr/share/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg"
        SSH "echo 'deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable' | tee /etc/apt/sources.list.d/syncthing.list"
        SSH "printf 'Package: *\nPin: origin apt.syncthing.net\nPin-Priority: 990\n' | tee /etc/apt/preferences.d/syncthing"
        SSH "apt update -y || true"
        SSH "apt install -y syncthing"
        SSH "systemctl enable syncthing@root"
        SSH "systemctl start syncthing@root"
    fi
    # Проверяем результат
    SSH_T "systemctl status --no-pager syncthing@root"

    # Добавляем папки
    local FOLDER_NAME="iso"
    local FOLDER_PATH="/var/lib/vz/template/iso"
    if ! SSH "syncthing cli config folders list | grep -q ${FOLDER_NAME}"
    then
        SSH "syncthing cli config folders add --id ${FOLDER_NAME} --path ${FOLDER_PATH}"
    fi

    # Настройка
    if Q "Объединить локальную и удаленную ноды Syncthing?"
    then
        # add local device to remote Syncthing
        local ID1=$(syncthing --device-id)
        SSH "syncthing cli config devices add --device-id ${ID1}"
        SSH "syncthing cli config devices ${ID1} auto-accept-folders set true"
        SSH "syncthing cli config devices ${ID1} introducer set true"

        # add remote device to local Syncthing
        local ID2=$(SSH "syncthing --device-id")
        eval "syncthing cli config devices add --device-id ${ID2}"
        eval "syncthing cli config devices ${ID2} auto-accept-folders set true"
        eval "syncthing cli config devices ${ID2} introducer set true"
        
        # share local folders to remote Syncthing
        for FOLDER in $(syncthing cli config folders list)
        do
            eval "syncthing cli config folders ${FOLDER} devices add --device-id ${ID2}"
        done

        # Проверка
        H2 "local devices list:"
        eval "syncthing cli config devices list"
        H2 "remote devices list:"
        SSH "syncthing cli config devices list"
        H2 "local folder list:"
        eval "syncthing cli config folders list"
        H2 "remote folder list:"
        SSH "syncthing cli config folders list"
    fi

    # Активируем shared режим для local storage
    SSH "pvesm set local --shared 1"

    # Проверяем, что синхронизация завершена
    local API_KEY=$(SSH "syncthing cli config gui apikey get")
    local URL="http://localhost:8384/rest/db/completion"
    # URL="http://localhost:8384/rest/db/completion?folder=default"
    H1 "Checking that replication is complete:"
    while true
    do
        sleep 10
        local COMPLETION=$(SSH "curl -s -X GET -H 'X-API-Key: ${API_KEY}' ${URL}")
        echo "${COMPLETION}"
        local PERCENTS=$(echo $COMPLETION | jq -r .completion)
        if [[ ${PERCENTS} == 100 ]]
        then
            break
        fi
    done
}

function 12_ETC_ENV {
    H1
    if Q "Скопировать /etc/environment на удаленный хост?"
    then
        local FILE="/etc/environment"
        cat ${FILE} | SSH "cat > ${FILE}"
    fi
}

function 13_UPDATE_SCRIPTS {
    H1
    local FOLDER="/root/Sync/pve-scripts"
    if ! SSH "[[ -e ${FOLDER} ]]"
    then
        # git@github.com:igluko/pve-scripts.git
        # https://github.com/igluko/pve-scripts.git
        SSH_T "git clone https://github.com/igluko/pve-scripts.git ${FOLDER}"
    else
        SSH_T "git -C ${FOLDER} pull https://github.com/igluko/pve-scripts.git"
    fi
}

function 6_VIRTIO_ISO {
    H1
    local WGET="wget -q --show-progress -N --progress=bar:force --content-disposition --directory-prefix=/var/lib/vz/template/iso/"
    # Latest:
    SSH_T "${WGET} https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
    # Latest for windows 7:
    SSH_T "${WGET} https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.173-9/virtio-win-0.1.173.iso"
    # Проверяем результат
    SSH_H2 "pvesm list local"
}

function 7_LICENSE {
    H1
    if SSH_T "pvesubscription get | tee /dev/tty | grep -q notfound"
    then
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
                    # Если лицензия успешно установлена, выходим из цикла
                    break   
                fi
            else
                # Если пользователь выбрал n, выходим из цикла
                break
            fi
        done
        # Спрашиваем у пользователя установить ли комьюнити репозитории
        local PVE_SCRIPTS="/root/Sync/pve-scripts"
        if ! SSH "${PVE_SCRIPTS}/setup-community-repo.sh --check"
        then
            if Q "Do you want to install community repositories?"
            then 
                SSH "${PVE_SCRIPTS}/setup-community-repo.sh"
            fi
        fi
    fi

    #  Меняем RU репозитории на обычные, RU еле шевелятся:
    SSH "sed -i s/\.ru\./\./ /etc/apt/sources.list"

    # Обносляем пакеты на сервере?
    if Q "Обновляем пакеты?"
        then
        SSH "apt update; apt dist-upgrade -y"
        if Q "Включаем новые возможности ZFS? (zpool upgrade)"
            then
            # Включаем новые возможности zfs, если таковые есть
            SSH "zpool upgrade rpool"
        fi
    fi
}

function 9_ENCRYPTION {
    H1
    H1 "Шифрование данных"

    local DATASET="rpool/data"

    if ! SSH "zfs get encryption -p -H ${DATASET} -o value | grep -q aes-256-gcm"
    then
        local FILE="/tmp/passphrase"
        # Задаем пароль шифрования ZFS
        if [[ -f $FILE ]]
        then
            local PASSWORD=$(cat $FILE)
            echo "Предложен пароль из файла $FILE с локального сервера"
        else
            echo "Пароль шифрования сгенерирован!"
            local PASSWORD=$( (tr -dc A-Za-z0-9 </dev/urandom || true) | head -c 20 ; echo )
        fi
        
        printf "\n${RED}Пароль шифрования ZFS:${NC}\n"
        read -e -p "> " -i "${PASSWORD}" PASSWORD

        # Создадим файл с ключом шифрования в папке /tmp
        SSH "echo ${PASSWORD} > ${FILE}"
        
        # Если датасет имеет вложенные объекты, то спрашиваем разрешение перед уничтожением!
        local ZFS_COUNT=$(SSH "zfs list ${DATASET} -r -H -o name | wc -l")

        if [[ ${ZFS_COUNT} -gt 1 ]]
        then
            Q "Внимание! ${DATASET} не пустой!!! Вы уверены, что хотите уничтожить его?" || return 0
            SSH "zfs destroy -r ${DATASET}"

        elif [[ ${ZFS_COUNT} -eq 1 ]]
        then
            SSH "zfs destroy -r ${DATASET}"
        fi

        SSH "zfs create -o encryption=on -o keyformat=passphrase -o keylocation=file:///tmp/passphrase rpool/data"
    fi
    # Проверяем результат
    SSH_H2 "zfs list -o name,encryption,keylocation,encryptionroot,keystatus"
}

function 8_ZFS {
    H1
    local POOL="rpool"

    SSH "zpool set autotrim=on ${POOL}"
    SSH "zfs set atime=off ${POOL}"
    SSH "zfs set compression=zstd-fast ${POOL}"

    SSH "echo 10779361280 >> /sys/module/zfs/parameters/zfs_arc_sys_free"

    local FILE="/etc/modprobe.d/zfs.conf"
    local TEXT="options zfs zfs_arc_sys_free=10779361280"

    if ! SSH "grep '${TEXT}' '${FILE}'" 2>&1 >/dev/null
    then
        SSH "echo '${TEXT}' > '${FILE}'"
        SSH "update-initramfs -u"
    fi

    # Проверяем результат   
    SSH_H2 "zpool list -o name,autotrim" 
    SSH_H2 "zfs list -o name,atime,compression"

    # SSH "zfs set primarycache=metadata rpool"

    # Нужно сделать для всех сторов
    SSH "pvesm set local-zfs --blocksize 16k"
}

function 22_SANOID {
    H1
    # ////////////////////
}

function PVE_INSTALL {

     
    # Шаг 10 - доверие между узлами
    printf "\n${ORANGE}Шаг 10 - доверие между узлами${NC}\n"
    echo "Пропущен"

    # Шаг 11 - добавление ноды в кластер
    printf "\n${ORANGE}Шаг 11 - добавление ноды в кластер${NC}\n"

    # Если на удаленной ноде нет кластера
    if ! SSH "pvecm status" 2>&1 >/dev/null
    then
        # Проверка параметров
        SSH_H2 "hostname"
        SSH_H2 "hostname -f"
        SSH_H2 "hostname -i"

        # Если на локальной ноде есть кластер, предлагаем добавить удаленную ноду в него
        if eval "pvecm status" 2>&1 >/dev/null
        then
            while true
            do
                Q "Добавить ноду в существующий кластер" || break
                # echo "Please take snapshot on ALL nodes, and add node to cluster"
                # read -e -p "> " -i "ok"
                # #${SSH[@]} "zfs snapshot -r rpool@before_cluster-${date +%s}"
                # pvecm add IP_ADDRESS_OF_EXISTING_NODE
                SSH_T "pvecm add ${IP_LOCAL}" && break
            done

        elif Q "Создать новый кластер?"
        then
            # Создание защитных снимков
            printf "\n${RED}Создание защитного снимка rpool/ROOT@before_cluster-$(date +%s)${NC}\n"
            SSH "zfs snapshot -r rpool/ROOT@before_cluster-$(date +%s)"
            printf "\n${RED}Enter cluster name ${NC}\n"
            read -p "> " ANSWER
            SSH_H2 "pvecm create ${ANSWER}"
        fi
        # Проверяем результат
        # SSH_H2 "pvecm status"
    fi

    # Шаг 13.1 - Патч Proxmox для работы с шифрованным ZFS и pve-zsync
    printf "\n${ORANGE}Шаг 13.1 - Патч Proxmox для работы с шифрованным ZFS и pve-zsync${NC}\n"
    FILE="/usr/share/perl5/PVE/Storage/ZFSPoolPlugin.pm"
    PATCH="/root/Sync/pve-scripts/ZFSPoolPlugin.pm.patch"
    ! SSH_T "patch --forward ${FILE} ${PATCH} 2>&1  | tee /dev/tty | grep -q failed"

    # Шаг 14 - pve-autorepl
    printf "\n${ORANGE}Шаг 14 - pve-autorepl${NC}\n"
    echo "Пропустили"

    # Шаг 15 - meminfo
    printf "\n${ORANGE}Шаг 15 - meminfo${NC}\n"
    SSH "/root/Sync/pve-scripts/notes.sh --add_cron"

    # Шаг 15.1 - ROOT reservation
    printf "\n${ORANGE}Шаг 15.1 - ROOT reservation${NC}\n"
    SSH_T "/root/Sync/pve-scripts/zfs-autoreservation.sh rpool/ROOT 5368709120"

    # Шаг 16 - swap через zRam
    printf "\n${ORANGE}Шаг 16 - swap через zRam${NC}\n"
    echo "Пропустили"

    # Шаг 17 - ebtables
    printf "\n${ORANGE}Шаг 17 - ebtables${NC}\n"
    if Q "Настроить ebtables?"
    then
        SSH "ip link"
        printf "\n${ORANGE}---${NC}\n"
        SSH_T "/root/Sync/pve-scripts/ebtables.sh"
    fi

    # Шаг 18 - bridge и vlan
    printf "\n${ORANGE}Шаг 18 - bridge и vlan${NC}\n"
    echo "Пропустили"

    # Шаг 18.1 - Добавление новых Bridge
    printf "\n${ORANGE}Шаг 18.1 - Добавление новых Bridge${NC}\n"
    echo "Пропустили"

    # Шаг 19 - Zabbix
    printf "\n${ORANGE}Шаг 19 - Zabbix${NC}\n"
    if Q "Настроить Zabbix?"
    then
        apt-install zabbix-agent
        SSH_T "sh /root/Sync/zabbix-agent/ConfigureZabbixAgent.sh"
    fi

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
        if SSH_T "/root/Sync/pve-scripts/etc_backup.sh"
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
        if SSH_T "/root/Sync/pve-scripts/backup-check.py"
        then
            # Добавляем скрипт в крон и выходим
            SSH_T "/root/Sync/pve-scripts/backup-check.py -add_cron" 
            break
        fi
    done

    # Шаг 23 - Sanoid
    printf "\n${ORANGE}Шаг 23 - Sanoid${NC}\n"

    if Q "Настроить переодические снимки через Sanoid?"
    then
        # Устанавливаем
        INSTALL sanoid
        # Меняем часовой пояс
        SSH "sed -i -E '/Environment=TZ=/ s/UTC/Europe\/Moscow/' /lib/systemd/system/sanoid.service"
        # Конфигурирование sanoid:
        SSH "mkdir -p /etc/sanoid"
        cat ${SCRIPTPATH}/sanoid.conf | SSH "cat > /etc/sanoid/sanoid.conf"
        # Перечитываем конфиги сервисов
        SSH "systemctl daemon-reload"
        # Проверка сервисов
        SSH_T "systemctl status --no-pager sanoid.timer"
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
        if SSH_T "/root/Sync/pve-scripts/sync-check.sh 1"
        then
            break
        fi
    done

    # Шаг 25 - Включение бота для клонов ZFS
    printf "\n${ORANGE}Шаг 25 - Добавление сборщика мусора для клонов ZFS в крон${NC}\n"
    SSH "/root/Sync/pve-zfsclone-bot/PVECloneBotGC.py -add_cron"
}

#-----------------------START-----------------------#

# Check terminal
if ! [[ -t 1 ]]
then
    echo "This script must be running in interactive mode"
    exit 1
fi

# # dummy SSH call to check connection, because next call in if statement and not stop if error
# SSH "true"

# Check the existence of the pve folder
if SSH "[[ -d /etc/pve ]]"
then
    # 0_ADD_PUBLIC_KEYS
    # 0_INSTALL_SOFTWARE
    # 2_FIREWALL
    # 3_DOCUMENTATION
    # 4_HOSTS
    # 5_TAB_NAME
    # 12_SYNCTHING
    # 12_ETC_ENV
    # 13_UPDATE_SCRIPTS
    # 6_VIRTIO_ISO
    # 7_LICENSE
    # 9_ENCRYPTION
    # 8_ZFS
    if type 22_SANOID | grep -q "is a function"
    then
        echo is a function
    fi
else
    ACTIVATE_RESCUE
    PVE_INSTALL
fi