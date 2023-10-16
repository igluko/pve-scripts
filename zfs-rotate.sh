#!/bin/bash

set -euo pipefail

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)

# add binary folders to local path
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Проверка наличия параметра "f<число>"
t_param_found=false
for arg in "$@"; do
    if echo "$arg" | grep -qE '^f[0-9]+$'; then
        t_param_found=true
        break
    fi
done

if ! $t_param_found; then
    echo "Ошибка: Один из параметров должен иметь формат 'f<число>'."
    echo "  Пример использования: zfs-rotate.sh f100000"
    echo "Возожные ключи и их описания:"
    echo "  f<int> - количество frequently снимков (обязательный параметр)"
    echo "  h<int> - количество hourly снимков"
    echo "  d<int> - количество daily снимков"
    echo "  m<int> - количество monthly снимков"
    echo "  y<int> - количество yearly снимков"
    exit 1
fi

for pool in $(zpool list -H -o name)
do
    output=$(zfs program $pool $SCRIPT_PATH/zfs-rotate.lua t$(date +%s) p$pool $@)

    if [[ -t 0 ]]; then
        # Если подключен файловый дескриптор терминала
        echo "$output"
    elif [[ $output =~ "failed" ]]; then
        # Если терминал не подключен, но в сообщении встретилась ошибка
        echo "$output"
    fi
done