#!/bin/bash

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
# load functions
source $SCRIPT_PATH/FUNCTIONS
# IFS=$' \n\t'
# ssh root@vinsent-FALC-01 "$(typeset -f INSTALL); INSTALL mc lnav"

function TEST2 {
    for i in "$@"
    do
        echo $i
    done
}

function SSH {
    # TT=$(printf "'%s' " "$@")
    # declare -p TT
    local SSH_OPT=(-C -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q)
    local COMMAND="$(typeset -f INSTALL INSERT); $@"

    ssh "${SSH_OPT[@]}" root@localhost "${COMMAND}"
}


for word in $( strings "$2" )
# Инструкция "strings" возвращает список строк в двоичных файлах.
# Который затем передается по конвейеру команде "grep", для выполнения поиска.
do
  echo $word
  exit
done

# Как указывает S.C., вышепрведенное объявление цикла for может быть упрощено
#    strings "$2" | grep "$1" | tr -s "$IFS" '[\n*]'