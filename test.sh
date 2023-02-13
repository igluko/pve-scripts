#!/bin/bash

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
# load functions
source $SCRIPT_PATH/FUNCTIONS

ssh root@vinsent-FALC-01 "$(typeset -f INSTALL); INSTALL mc lnav"

