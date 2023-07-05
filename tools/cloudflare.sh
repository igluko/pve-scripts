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

# Проверяем что количество аргументов равно 2
if [ "$#" -ne 2 ]; then
    echo "Illegal number of parameters"
    echo "Usage: $0 <RECORD> <NEW_IP>"
    exit 1
fi

INSTALL jq

# Если скрипт запущен в интерактивном режиме, то запрашиваем API_TOKEN, иначе загружаем из файла
if [[ -t 0 ]]; then
    UPDATE API_TOKEN ${SCRIPT}.env
else
    LOAD ${SCRIPT}.env
fi


# Test cloudflare api call
curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" \
-H "Authorization: Bearer ${API_TOKEN}" | jq .messages[].message

RECORD=${1}
H1 RECORD=${RECORD}

# Если домен не содержит ни одной точки, то выходим
if [[ $RECORD != *"."* ]]; then
    echo "RECORD name is not valid domain name (example.com)"
    exit 1
fi

ZONE=$(echo ${RECORD} | awk -F. '{print $(NF-1) FS $NF}')
H1 ZONE=$ZONE

CONTENT=${2}
H1 CONTENT=${CONTENT}

# Получаем ID зоны
ZONE_ID=$(curl -s --request GET \
  --url https://api.cloudflare.com/client/v4/zones?name=${ZONE} \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer ${API_TOKEN}" | jq -r .result[0].id)

H1 ZONE_ID=${ZONE_ID}

# Если ID зоны не получен, то выходим
if [[ -z ${ZONE_ID} ]]; then
    echo "Zone ID is not valid"
    exit 1
fi

# Получаем ID записи
# Ограничиваем тип записи 2 значениями A и CNAME
RECORD_ID=$(curl -s --request GET \
  --url https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${RECORD}\&type=A,CNAME \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer ${API_TOKEN}" | jq -r .result[0].id)

H1 RECORD_ID=${RECORD_ID}

# Если ID записи не получен, то выходим
if [[ -z ${RECORD_ID} ]]; then
    echo "Record ID is not valid"
    exit 1
fi

TYPE="A"

# Изменяем DNS запись
curl -s --request PATCH \
  --url https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID} \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer ${API_TOKEN}" \
  --data "{
  \"content\": \"${CONTENT}\"
}" | jq .






