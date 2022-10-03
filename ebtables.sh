#!/bin/bash
# Helpful to read output when debugging
# set -x

# This script prevents Hetzner Abuse Message : MAC-Errors
function helpEnv {
    echo "Please set variables in /etc/environment"
    echo "Examples:"
    echo "  EBTABLES=enp7s0,00:50:56:00:CD:33,00:50:56:00:CD:34"
}

function readEnv {
    # read envivoments
    source  /etc/environment
}

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`
# add binary folders to local path
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

#https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color
OK="${GREEN} ok ${NC}"
FAIL="${RED}fail${NC}"
WARN="${ORANGE}warn${NC}"

function 3party {
    # install 3 party software
    if ! dpkg -s inotify-tools >/dev/null ; then
        printf "[$WARN] inotify-tools not installed\n"
        apt update 
        apt install inotify-tools -y
    fi
}

function checkError {
    if [[ "$?" -eq 0 ]]; then
        printf "[$OK] $1 \n"
    else
        printf "[$FAIL] $1 \n" >&2
        exit 1
    fi
}

function run {
	eval "$1"
    checkError "$1"
}

function checkVar {
    if [[ -n "${!1}" ]]; then
        printf "[$OK] "${1}" => "${!1}" \n"
    else
        printf "[$FAIL] "${1}" is empty \n" >&2
        exit 1
    fi
}

function checkEnv {
    if [[ -n "${!1}" ]]; then
        printf "[$OK] "${1}" => "${!1}" \n"
    else
        printf "[$FAIL] "${1}" is empty \n" >&2
        helpEnv >&2
        exit 1
    fi
}

function cron {
    TASK="@reboot $SCRIPT"
    if crontab -l 2>/dev/null | grep -F -q "$TASK"
    then 	
        echo "task already has been added to crontab"
    else
        (crontab -l 2>/dev/null; echo "$TASK") | crontab -
    fi
}

function main {
    run "readEnv"

    run "3party"

    checkEnv EBTABLES

    IFACE=$(echo $EBTABLES | cut -d, -f1)
    checkVar IFACE

    MAC=$(echo $EBTABLES | cut -d, -f2-)
    checkVar MAC

    run "ebtables -F"
    run "ebtables -I FORWARD -o $IFACE -p IPv4 --among-src ! $MAC --log-level info --log-prefix MAC-FLOOD-F --log-ip -j DROP"
    run "ebtables -L"
    
    run "cron"
}

# Suppress output if non-interacive mode
if [ -t 1 ] ; then 
    main
else
    main >/dev/null
    while inotifywait -q -e close_write /etc/environment; do
        main >/dev/null
    done
fi

