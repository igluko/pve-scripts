#!/bin/bash
# set -x

set -euo pipefail

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)

TIME=$(date +"%Y-%m-%d_%H:%M:%S")

# add binary folders to local path
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

get_running_vm_vmids() {
    qm list | awk '$3 == "running" { printf "vm-%s-|", $1 }'
}

get_running_ct_vmids() {
    pct list | awk '$2 == "running" { printf "subvol-%s-|", $1 }'
}

# Используем функции для получения списка запущенных VM и контейнеров
running_vmids="$(get_running_vm_vmids)$(get_running_ct_vmids)"

# Удалить последний символ "|"
running_vmids=${running_vmids%|}

# Получаем список zfs пулов
zfs_pools=$(zpool list -H -o name)

for pool in $zfs_pools; do
    #   Получаем список всех файловых систем с нужными свойствами
    all_datasets=$(zfs list -H -o name,label:nosnap,label:running -r $pool)

    # Получаем 2 списка датасетов 1) с запущенными VM 2) без запущенных VM
    if [ -z "$running_vmids" ]; then
        running_datasets=""
        not_running_datasets="$all_datasets"
    else
        running_datasets=$(echo "$all_datasets" | grep -E "$running_vmids")
        not_running_datasets=$(echo "$all_datasets" | grep -vE "$running_vmids")    
    fi

    ## stopped -> running
    # находим датасеты, которые нуждаются в свойстве label:running и проставляем его
    # не используем zfs program: запуск\остановка VM - редкоя операция
    for dataset in $(echo "$running_datasets" | awk '($3 != "running"){print $0}'); do
         zfs set label:running=running $dataset
    done

    #  фильтруем: оставляем те, где label:nosnap == nosnap,
    #  формируем однострочный список параметров
    snapshot_datasets=$(echo "$running_datasets" | awk '($2 != "nosnap"){print $1}' | tr '\n' ' ')

    # Если cписок не пустой, вызываем другой скрипт
    if [[ ! -z "$snapshot_datasets" ]]; then
        output=$(zfs program $pool $SCRIPT_PATH/zfs-snapshot.lua $TIME $snapshot_datasets)

        if [[ -t 0 ]]; then
            # Ввод идет из терминала
            echo "$output"
        elif [[ $output =~ "failed" ]]; then
            echo "$output"
        fi
    fi

    # Делаем служебные снимки только что остановленных VM
    #   Это нужно для отслеживания актуальности репликаций на приемнике
    #       Если новых снимков для датасета давно не поступало, приемник должен алертить
    #       Но если последний снимок, помечен как stopped, приемник может не беспокоиться
    # Используем служебное свойство label:running для отслеживания изменения состояния VM

    ## running -> stopped
    # echo "$not_running_datasets"
    for dataset in $(echo "$not_running_datasets" | awk '($3 == "running"){print $1}'); do
        zfs inherit label:running $dataset
        zfs snapshot $dataset@autosnap_${TIME}_frequently_stopped
    done
    
done