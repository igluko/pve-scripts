#!/bin/bash

###
# This script is needed to setup a community version of Proxmox VE 5.x-7.x
###

# Helpful to read output when debugging
# set -x

#https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Strict mode
set -eEuo pipefail
# set -eEu
trap 'printf "${RED}Failed on line: $LINENO at command:${NC}\n$BASH_COMMAND\nexit $?\n"' ERR
IFS=$'\n\t'

#-----------------------START-----------------------#

FILE1="/etc/apt/sources.list.d/pve-enterprise.list"

FILE2="/etc/apt/sources.list.d/pve-no-enterprise.list"
TEXT2="deb http://download.proxmox.com/debian/pve $(grep "VERSION=" /etc/os-release | sed -n 's/.*(\(.*\)).*/\1/p') pve-no-subscription"

if [[ $# -eq 1 ]] && [[ $1 = "--check" ]]
then
    grep -q "^#deb" ${FILE1} && exit 0 || exit 1
    grep -q ${TEXT2} ${FILE2} && exit 0 || exit 1
fi

# Disable Commercial Repo
sed -i "s/^deb/\#deb/" ${FILE1}
apt-get update

# Add PVE Community Repo
echo "${TEXT2}" > ${FILE2}
apt-get update


