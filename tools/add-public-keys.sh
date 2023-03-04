#!/bin/bash

# IFS (Internal Field Separator) variable is used to specify the delimiter(s) used when parsing strings into fields or when splitting strings
IFS=$'\n\t'

# Функция заменит строку в файле, если совпадет MATCH условие
function INSERT {
    local FILE="${1}"
    local REPLACE="${2}"

    touch ${FILE}

    if [[ $# -eq 2 ]]
    then
        MATCH="$2"
    else
        MATCH="$3"
    fi

    if ! grep -q "${MATCH}" "${FILE}"
    then
        echo "${REPLACE}" >> "${FILE}"
    else
        ESCAPED_REPLACE=$(printf '%s\n' "$REPLACE" | sed -e 's/[\/&]/\\&/g')
        ESCAPED_MATCH=$(printf '%s\n' "$MATCH" | sed -e 's/[\/&]/\\&/g')
        sed -i '/${ESCAPED_MATCH}/ s/.*/${ESCAPED_REPLACE}/' "${FILE}"
    fi
}

echo "Add public keys from authorized_keys.g00.link"

if ! [[ -d /root/.ssh ]]
then
    mkdir /root/.ssh
    chmod 700 /root/.ssh
fi

TXT_LIST=$(dig authorized_keys.g00.link +short -t TXT | sed 's/" "//g'| xargs -n1)
for TXT in ${TXT_LIST}
do
    INSERT /root/.ssh/authorized_keys "${TXT}"
done
