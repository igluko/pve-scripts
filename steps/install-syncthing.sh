#!/bin/bash

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname ${SCRIPT})
# load functions
if ! [[ -e ${SCRIPT_PATH}/FUNCTIONS ]]
then
    FILE_URL="https://raw.githubusercontent.com/igluko/pve-scripts/main/FUNCTIONS"
    source <(curl -sSL ${FILE_URL})
else
    source ${SCRIPT_PATH}/FUNCTIONS
fi

# Install software
INSTALL "jq"

# Установка
if ! eval "which syncthing >/dev/null"
then
    eval "curl -s -o /usr/share/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg"
    eval "echo 'deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable' | tee /etc/apt/sources.list.d/syncthing.list"
    eval "printf 'Package: *\nPin: origin apt.syncthing.net\nPin-Priority: 990\n' | tee /etc/apt/preferences.d/syncthing"
    eval "apt update -y || true"
    eval "apt install -y syncthing"
    eval "systemctl enable syncthing@root"
    eval "systemctl start syncthing@root"
fi
# Проверяем результат
eval "systemctl status --no-pager syncthing@root"

# Добавляем в syncthing папку iso, если она присутствует на хосте
FOLDER_NAME="iso"
FOLDER_PATH="/var/lib/vz/template/iso"
if [[ -f "${FOLDER_PATH}" ]]
then
    if ! eval "syncthing cli config folders list | grep -q ${FOLDER_NAME}"
    then
        eval "syncthing cli config folders add --id ${FOLDER_NAME} --path ${FOLDER_PATH}"
    fi
    # Активируем shared режим для local storage
    eval "pvesm set local --shared 1"
fi

# Настройка
if Q "Подключить эту ноду Syncthing к другой ноде?"
then
    H1 "Внимание, сейчас будет предложено ввести IP адрес соседней ноды!"
    SSH "true"
    H1 "Имя удаленной машины: $(SSH "hostname -f")"
    Q "Продолжаем?" || exit
    # add local device to remote Syncthing
    ID1=$(syncthing --device-id)
    SSH "syncthing cli config devices add --device-id ${ID1}"
    SSH "syncthing cli config devices ${ID1} auto-accept-folders set true"
    SSH "syncthing cli config devices ${ID1} introducer set true"

    # add remote device to local Syncthing
    ID2=$(SSH "syncthing --device-id")
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

# Проверяем, что синхронизация завершена
API_KEY=$(eval "syncthing cli config gui apikey get")
URL="http://localhost:8384/rest/db/completion"
# URL="http://localhost:8384/rest/db/completion?folder=default"
H1 "Checking that replication is complete:"
while true
do
    sleep 10
    COMPLETION=$(eval "curl -s -X GET -H 'X-API-Key: ${API_KEY}' ${URL}")
    echo "${COMPLETION}"
    PERCENTS=$(echo $COMPLETION | jq -r .completion)
    if [[ ${PERCENTS} == 100 ]]
    then
        break
    fi
done