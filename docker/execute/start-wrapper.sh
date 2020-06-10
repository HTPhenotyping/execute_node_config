#!/bin/bash

fail() {
    echo "ERROR:    $*" 1>&2
    exit 1
}

if [ "$(id -u)" != "0" ]; then
    fail "Docker must be run with root privileges"
fi

# Check that the central manager and data source names have been set
for key in CONDOR_HOST UniqueName; do
    value="$(condor_config_val $key 2>/dev/null)" || \
	fail "Did not find $key in the HTCondor config"
    [[ "$value" == "changeme" || "$value" == '"changeme"' ]] && \
	fail "HTCondor config key $key must changed from the default value"
done

# Grab central manager and data source names, stripping quotes
CENTRAL_MANAGER="$(condor_config_val CONDOR_HOST | sed -e 's/^"//' -e 's/"$//')"
DATA_SOURCE_NAME="$(condor_config_val UniqueName | sed -e 's/^"//' -e 's/"$//')"

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
