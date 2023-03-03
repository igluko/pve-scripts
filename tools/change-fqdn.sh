#!/bin/bash

###
# This script is needed to change the FQDN of a proxmox node
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

    if ! eval "grep -q \"${MATCH}\" ${FILE}"
    then
        eval "echo \"${REPLACE}\" >> ${FILE}"
    else
        ESCAPED_REPLACE=$(printf '%s\n' "$REPLACE" | sed -e 's/[\/&]/\\&/g')
        ESCAPED_MATCH=$(printf '%s\n' "$MATCH" | sed -e 's/[\/&]/\\&/g')
        eval "sed -i '/${ESCAPED_MATCH}/ s/.*/${ESCAPED_REPLACE}/' ${FILE}"
    fi
}

#-----------------------START-----------------------#

OLD_FQDN=$(hostname -f)
read -r -e -p "> " -i "$OLD_FQDN" NEW_FQDN

if [[ ${OLD_FQDN} = ${NEW_FQDN} ]]
then
    echo "Nothing to change. Exit"
fi

# Extract the HOSTNAME and DOMAIN using sed
NEW_HOSTNAME=$(echo "$NEW_FQDN" | sed 's/\..*//')
# NEW_DOMAIN=$(echo $NEW_FQDN | sed 's/[^.]*.//')
IP=$(hostname -i)

# Update hostname
hostnamectl set-hostname ${NEW_HOSTNAME}

# Update hosts file
FILE="/etc/hosts"
MATCH="${IP}"
REPLACE="${IP} ${NEW_FQDN} ${NEW_HOSTNAME}"
insert "${FILE}" "${REPLACE}" "${MATCH}"

# Update main.cf file
FILE="/etc/postfix/main.cf"
MATCH="myhostname"
REPLACE="myhostname=${NEW_FQDN}"
insert "${FILE}" "${REPLACE}" "${MATCH}"

# Переносим файлы конфигураций из старых папок в новые:
# mv /etc/pve/nodes/pve/qemu-server/* /etc/pve/nodes/vinsent-MSK-01/qemu-server/
 
# mv /etc/pve/nodes/pve/lxc/* /etc/pve/nodes/vinsent-MSK-01/lxc/
 
# Удаляем старую папку:
# rm -rf /etc/pve/nodes/pve

