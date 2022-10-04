#!/bin/bash

###
# This script prevents Hetzner Abuse Message : MAC-Errors
###

# Helpful to read output when debugging
# set -x

#https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color
OK="${GREEN} done ${NC}"
FAIL="${RED}failed${NC}"
WARN="${ORANGE}warning${NC}"

# Strict mode
set -eEuo pipefail
trap 'printf "${RED}Failed on line: $LINENO at command:${NC}\n$BASH_COMMAND\nexit $?\n"' ERR
IFS=$'\n\t'

# read envivoments
source  /etc/environment
# get real path to script
SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`
# add binary folders to local path
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

function run {
	eval "$1"
    printf "[$OK] $1 \n"
}

function cron-update {
    TASK="@reboot $SCRIPT"
    if crontab -l 2>/dev/null | grep -F -q "$TASK"
    then 	
        echo "task already has been added to crontab"
    else
        (crontab -l 2>/dev/null; echo "$TASK") | crontab -
    fi
}

function save {
    local VARIABLE="${1}"
    local VALUE="$(echo ${!1} | xargs)"
    local FILE="${2}"

    if grep -q ^${VARIABLE}= $FILE
    then
        eval "sed -i -E 's/${VARIABLE}=.*/${VARIABLE}=\"${VALUE}\"/' $FILE"
    else
        echo "${VARIABLE}=\"${VALUE}\"" >> $FILE
    fi
}

function main {
    IFACE=$(echo $EBTABLES | cut --delimiter ',' --fields 1)
    MAC=$(echo $EBTABLES | cut --delimiter ',' --only-delimited --fields 2-)
    
    run "ebtables -t filter -F"

    if [[ -n "$MAC" ]]
    then
        run "ebtables -t filter -I FORWARD -o $IFACE --among-src ! $MAC --log-level info --log-prefix MAC-FLOOD-F --log-ip -j DROP"
    else
        run "ebtables -t filter -I FORWARD -o $IFACE --log-level info --log-prefix MAC-FLOOD-F --log-ip -j DROP"
    fi
}

# Setup if interacive mode  Suppress output if non-interacive mode
if [ -t 1 ] ; then
    # make sure that variable is set
    if [[ ! -v EBTABLES ]];
    then
        EBTABLES=""
    fi
    echo "Please input config string (example: enp7s0,00:50:56:00:CD:33,00:50:56:00:CD:34)"
    read -e -p "> " -i "${EBTABLES}" EBTABLES
    save EBTABLES "/etc/environment"
    main
    run "cron-update"
else
    main >/dev/null
fi