#!/bin/bash

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname ${SCRIPT})

# awk нужен, чтобы вырезать нули в начале числа
HOURS=$(date +%H | awk -F: '{print +$1}')
MINUTES=$(date +%M | awk -F: '{print +$1}')

# Тест A записей
# Перенаправление ввода нужно, чтобы запустить скрипт в неинтерактивном режиме
${SCRIPT_PATH}/cloudflare.sh test.g00.link 0.0.${HOURS}.${MINUTES} < /dev/null