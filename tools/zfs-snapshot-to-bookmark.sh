#!/bin/bash

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
# load functions
source $SCRIPT_PATH/../FUNCTIONS

# setup snapshot prefix
SNAPSHOT_PREFIX=syncoid
UPDATE "SNAPSHOT_PREFIX"

# find snapshots
SNAPSHOTS=$(zfs list -t snapshot -o name -H | (grep @${SNAPSHOT_PREFIX} || true) | tee /dev/tty)
if [[ ${SNAPSHOTS} == "" ]]
then
    echo "Snapshots not found, exit"
    exit
fi

# convert snapshots to bookmarks
if Q "Convert these snapshots into bookmarks?"
then
    for SNAPSHOT in ${SNAPSHOTS}
    do
        BOOKMARK=$(echo ${SNAPSHOT} | tr "@" "#" | tee /dev/tty)
        zfs bookmark ${SNAPSHOT} ${BOOKMARK} || true
        zfs destroy ${SNAPSHOT} || true
    done
fi