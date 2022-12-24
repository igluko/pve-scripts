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
#set -eEu
#trap 'printf "${RED}Failed on line: $LINENO at command:${NC}\n$BASH_COMMAND\nexit $?\n"' ERR
# IFS=$'\n\t'

# read envivoments
source  /etc/environment
# get real path to script
SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`
# add binary folders to local path
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

IPS=$(cat /etc/corosync/corosync.conf | grep ring0_addr | sed "s/.*ring0_addr: //")


while true
do
    printf "\n${ORANGE}Please enter command${NC}\n"
    read -r -e -p "> " -i "" COMMAND

    for IP in ${IPS}
    do
        printf "\n${ORANGE}${IP}${NC}\n"
        SSH="ssh root@${IP}"
        printf ${ORANGE}
        ${SSH} hostname
        printf ${NC}
        ${SSH} "${COMMAND}"
    done
done

