#!/bin/bash

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

# Update config
sed -i "s/changeme/$CENTRAL_MANAGER/"  /etc/condor/config.d/10-CentralManager
sed -i "s/changeme/$DATA_SOURCE_NAME/" /etc/condor/config.d/20-UniqueName

# Check for valid token by doing a condor_status with only IDTOKENS
_CONDOR_SEC_CLIENT_AUTHENTICATION_METHODS=IDTOKENS condor_status -limit 1 >/dev/null 2>&1 || {
    # Request token if condor_status fails
    echo
    echo "Finishing registration of $DATA_SOURCE_NAME with $CENTRAL_MANAGER..."
    echo
    register_url="https://raw.githubusercontent.com/HTPhenotyping/registration/master/register.py"
    register_path="/register.py"
    wget "$register_url" -O "$register_path" >/dev/null 2>&1 || fail "Could not download register.py"
    chmod u+x "$register_path" || fail "Could not set permissions on register.py"
    $register_path --pool="$CENTRAL_MANAGER" --source="$DATA_SOURCE_NAME" && {
	_CONDOR_SEC_CLIENT_AUTHENTICATION_METHODS=IDTOKENS condor_status -limit 1 >/dev/null 2>&1 || {
	    fail "Registration completed, but the machine could not authenticate with $CENTRAL_MANAGER"
	}
    } || fail "Could not register with $CENTRAL_MANAGER"
}

# run start.sh
CONDOR_HOST="$CENTRAL_MANAGER" /bin/bash /start.sh
