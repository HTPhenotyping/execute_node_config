#!/bin/bash

usage() {
    echo "Usage: $0" 1>&2
    echo "    -i Run initialization" 1>&2
    echo "    -c (Required if -i) <Central Manager Hostname>" 1>&2
    echo "    -n (Required if -i) <Data Source Name>" 1>&2
    exit 1
}

fail() {
    echo "ERROR:    $*" 1>&2
    exit 1
}

RUN_INIT="false"
while getopts "ic:n:" OPTION; do
    case "$OPTION" in
        i)
            RUN_INIT="true"
            ;;
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
[[ "$RUN_INIT" == "true" && (-z $CENTRAL_MANAGER || -z $DATA_SOURCE_NAME) ]] && usage

# Check root
[[ "$(id -u)" != "0" ]] && fail "Docker must be run with root privileges"

# Check for required directories
for reqdir in config.d tokens.d; do
    if [[ ! -d "/etc/condor/$reqdir" ]]; then
        fail "Required directory /etc/condor/$reqdir does not exist"
    fi
done

if [[ "$RUN_INIT" == "true" ]]; then

    # Set up config
    echo "Downloading, modifying, and installing HTCondor configuration..."
    tmp_dir="/tmp/install_htcondor-$$"
    config_repo="https://github.com/HTPhenotyping/execute_node_config.git"
    mkdir -p "$tmp_dir" || fail "Could not create temporary directory $tmp_dir"
    pushd "$tmp_dir" >/dev/null && {
        git clone $config_repo >/dev/null 2>&1 || fail "Could not clone git repo $config_repo"
        sed -i "s/changeme/$CENTRAL_MANAGER/"  execute_node_config/config.d/10-CentralManager
        sed -i "s/changeme/$DATA_SOURCE_NAME/" execute_node_config/config.d/20-UniqueName
        sed -i "s/changeme/docker/"            execute_node_config/config.d/21-InstallUser
        sed -i "s|changeme|/mnt/data|"         execute_node_config/config.d/22-DataDir
        sed -i "s/nobody/slot1/"               execute_node_config/config.d/23-SlotUser
        mv execute_node_config/config.d/* "/etc/condor/config.d/" || fail "Could not install config files from $tmp_dir"
    }
    popd >/dev/null
    echo "ENABLE_KERNEL_TUNING=False" > "/etc/condor/config.d/01-Docker"
    rm -rf "$tmp_dir" 2>/dev/null || warn "Could not remove temporary directory $tmp_dir"

fi

# Check that the central manager and data source names have been set
for key in CONDOR_HOST UniqueName; do
    value="$(condor_config_val $key 2>/dev/null | sed -e 's/^"//' -e 's/"$//')" || \
        fail "Did not find $key in the HTCondor config"
    [[ "$value" == "changeme" ]] && \
        fail "HTCondor config key $key must changed from the default value"
done

# Grab central manager and data source names, stripping quotes
CENTRAL_MANAGER="$(condor_config_val CONDOR_HOST | sed -e 's/^"//' -e 's/"$//')"
DATA_SOURCE_NAME="$(condor_config_val UniqueName | sed -e 's/^"//' -e 's/"$//')"

# Check for valid token by doing a condor_status with only IDTOKENS
_CONDOR_SEC_CLIENT_AUTHENTICATION_METHODS=IDTOKENS condor_status -limit 1 >/dev/null 2>&1 || {
    # Request token if condor_status fails
    if [[ "$RUN_INIT" == "true" ]]; then
        echo
        echo "Finishing registration of $DATA_SOURCE_NAME with $CENTRAL_MANAGER"
        echo "and obtaining credentials for this machine."
        echo
    else
        echo
        echo "Credentials for this machine have expired, obtaining new credentials by"
        echo "re-finishing registration, please follow the instructions below."
        echo
    fi
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
