#!/bin/bash

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
# load functions
source $SCRIPT_PATH/../FUNCTIONS

PACKAGE="sanoid"
VERSION="2.1.0"

# Проверяем установлен ли пакет
if dpkg -l | awk '$1=="ii" {print $0}' | grep ${PACKAGE}
then
    # Проверяем версию
    if dpkg -l | awk '$1=="ii" {print $0}' | grep ${PACKAGE} | grep -q ${VERSION}
    then
        # Нужная версия уже стоит
        exit 0
    else
        # Удаляем старую версию
        apt remove ${PACKAGE} -y
    fi
fi

# Устанавливаем пакет
apt update || true
apt install -y debhelper libcapture-tiny-perl libconfig-inifiles-perl pv lzop mbuffer build-essential git

cd /tmp
[[ -e /tmp/sanoid ]] && rm -rf /tmp/sanoid
rm -rf /tmp/sanoid
git clone https://github.com/jimsalterjrs/sanoid.git
cd sanoid
git checkout $(git tag | grep "^v" | tail -n 1)
ln -s packages/debian .
dpkg-buildpackage -uc -us
apt install ../sanoid_*_all.deb

# После переустановки (обновления) службы будут маскированы
systemctl unmask sanoid.timer
systemctl unmask sanoid-prune.service

# Запуск служб
systemctl enable sanoid.timer
systemctl start sanoid.timer

# Нужно поменять часовой пояс сервиса
sed -i -E '/Environment=TZ=/ s/UTC/Europe\/Moscow/' /lib/systemd/system/sanoid.service
systemctl daemon-reload
systemctl restart sanoid