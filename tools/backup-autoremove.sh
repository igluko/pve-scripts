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

# Проверяем что количество аргументов равно 1
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <default keep days>"
    echo "Example: $0 180"
    exit 1
fi

BACKUP_DIR="/var/lib/vz/dump/"
DEFAULT_KEEP_DAYS=${1}

if ! [[ "$DEFAULT_KEEP_DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: Provided default keep days is not a number."
    exit 2
fi

# Add to cron if terminal exist
if [[ -t 1 ]]
then
    TASK="33 4 * * * ${SCRIPT} $*"
    if crontab -l 2>/dev/null | grep -F -q "${TASK}"
    then
        echo "task already has been added to crontab"
    else
        (crontab -l 2>/dev/null || true; echo "$TASK") | crontab -
    fi
fi

currentTime=$(date +%s)
maxAgeInSeconds=$((DEFAULT_KEEP_DAYS * 24 * 3600))

# Поиск всех файлов бэкапа
find "$BACKUP_DIR" -name "*.log" | while read -r logFile; do
    # Сравниваем время создания файла с текущим временем
    fileAge=$(stat -c '%Y' "$logFile")
    if [ $((currentTime - fileAge)) -gt $maxAgeInSeconds ]; then
        baseName="${logFile%.log}"
        # Удаление всех связанных файлов
        rm -f "$baseName"*
    fi
done

exit 0