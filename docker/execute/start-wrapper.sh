#!/bin/bash

prog=${0##*/}
progdir=${0%/*}

usage() {
    echo "Usage: $0 -c <Central Manager Hostname> -n <Data Source Name>" 1>&2
    exit 1
}

fail() {
    echo "ERROR:    $*" 1>&2
    exit 1
}

while getopts "c:n:" OPTION; do
    case "$OPTION" in
	c)
	        CENTRAL_MANAGER="$OPTARG"
		    ;;
	n)
	        DATA_SOURCE_NAME="$OPTARG"
		    ;;
	\?)
	        usage
		    ;;
    esac
done

if [ "$(id -u)" != "0" ]; then
    fail "Docker must be run with root privileges"
fi

DEFAULT_CENTRAL_MANAGER="htpheno-cm.chtc.wisc.edu"

if [[ -z "$CENTRAL_MANAGER" || -z "$DATA_SOURCE_NAME" ]]; then
    echo
    echo "Respond to the following prompts following the installation page"
    echo
    echo "Leave responses empty to accept the [default value] in square brackets."
    echo
fi

# Check for central manager
while [[ -z "$CENTRAL_MANAGER" ]]; do
    read -p "Central manager hostname [$DEFAULT_CENTRAL_MANAGER]: " CENTRAL_MANAGER
    [[ -z "$CENTRAL_MANAGER" ]] && [[ ! -z "$DEFAULT_CENTRAL_MANAGER" ]] && \
	CENTRAL_MANAGER="$DEFAULT_CENTRAL_MANAGER"
done
if [[ ! "$CENTRAL_MANAGER" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
    fail "The central manager hostname must be a valid hostname"
fi

# Check for data source name
while [[ -z "$DATA_SOURCE_NAME" ]]; do
    read -p "Preferred data source name [$DEFAULT_DATA_SOURCE_NAME]: " DATA_SOURCE_NAME
    [[ -z "$DATA_SOURCE_NAME" ]] && [[ ! -z "$DEFAULT_DATA_SOURCE_NAME" ]] && \
	DATA_SOURCE_NAME="$DEFAULT_DATA_SOURCE_NAME"
done
if [[ ! "$DATA_SOURCE_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
    fail "The data source name may only contain alphanumeric characters and underscores"
fi

sed -i "s/changeme/$CENTRAL_MANAGER/"  /etc/condor/config.d/10-CentralManager
sed -i "s/changeme/$DATA_SOURCE_NAME/" /etc/condor/config.d/20-UniqueName

echo
echo "Finishing data source $DATA_SOURCE_NAME registration with $CENTRAL_MANAGER..."
echo
# Using register.py from master:
# https://github.com/HTPhenotyping/registration/blob/master/register.py
register_url="https://raw.githubusercontent.com/HTPhenotyping/registration/master/register.py"
register_path="/usr/sbin/register.py"
wget "$register_url" -O "$register_path" || fail "Could not download register.py"
chmod u+x "$register_path" || fail "Could not set permissions on register.py"
register.py --pool="$CENTRAL_MANAGER" --source="$DATA_SOURCE_NAME" && {
    condor_status -limit 1 || {
	echo
	fail "Registration completed, but the machine could not talk to the central manager"
    }
} || fail "Could not register with $CENTRAL_MANAGER"

# run start.sh
CONDOR_HOST=$CENTRAL_MANAGER /bin/bash -x /start.sh
