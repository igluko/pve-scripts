#!/bin/bash

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
# load functions
source $SCRIPT_PATH/../FUNCTIONS

echo "Add public keys from authorized_keys.g00.link"

TXT_LIST=$(dig authorized_keys.g00.link +short -t TXT | sed 's/" "//g'| xargs -n1)
for TXT in ${TXT_LIST}
do
    INSERT /root/.ssh/authorized_keys '${TXT}'
done
