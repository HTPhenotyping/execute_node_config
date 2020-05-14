#!/bin/bash
# This script deploys HTCondor according to the configs in
# https://github.com/HTPhenotyping/execute_node_config .
# It requires the user supply the central manager hostname,
# a unique name to identify this machine, and the path that
# users are expected to transfer data from.
# This script must run with root privileges as it installs
# many packages and modifies system configuration.

usage() {
    echo "Usage: $0 -c <Central Manager Hostname> -d <Data Source Directory> -n <Data Source Name>" 1>&2
    exit 1
}

priv_error() {
    echo "This script must be run as root or with sudo"
    exit 1
}

fail_noexit() {
    echo "ERROR:    $*" 1>&2
}

fail() {
    echo "ERROR:    $*" 1>&2
    echo "Check $LOGFILE for more details" 1>&2
    exit 1
}

warn() {
    echo "WARNING:     $*" 1>&2
}

while getopts "c:d:n:" OPTION; do
    case "$OPTION" in
	c)
	    CENTRAL_MANAGER="$OPTARG"
	    ;;
	d)
	    DATA_SOURCE_DIRECTORY="$OPTARG"
	    ;;
	n)
	    DATA_SOURCE_NAME="$OPTARG"
	    ;;
	\?)
	    usage
	    ;;
    esac
done

# Set up logging https://askubuntu.com/a/1001404
LOGFILE="/tmp/install_htcondor.$$.log"
exec 19> $LOGFILE
BASH_XTRACEFD=19
set -x

# Check for root
if [ "$(id -u)" != "0" ]; then
    priv_error
fi

# Check for central manager
while [ -z "$CENTRAL_MANAGER" ]; do
    read -p "Central manager hostname: " CENTRAL_MANAGER
done
if [[ ! "$CENTRAL_MANAGER" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
    fail_noexit "The central manager hostname must be a valid hostname"
    echo "Please check your input and try again" 1>&2
    exit 1
fi

# Check for data source name
while [ -z "$DATA_SOURCE_NAME" ]; do
    read -p "Preferred data source name (e.g. MyUniversity_Smith): " DATA_SOURCE_NAME
done
if [[ ! "$DATA_SOURCE_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
    fail_noexit "The data source name may only contain alphanumeric characters and underscores"
    echo "Please check your input and try again" 1>&2
    exit 1
fi

# Check for data source directory
while [ -z "$DATA_SOURCE_DIRECTORY" ]; do
    read -p "Data source directory (e.g. /mnt/external/images): " DATA_SOURCE_DIRECTORY
done

# Run tests on directory
if [[ ! "$DATA_SOURCE_DIRECTORY" =~ ^/ ]]; then
    fail_noexit "The data source directory must be an absolute path"
    echo "The data source directory must be the full path, starting with /" 1>&2
    exit 1
fi
if [[ ! -d "$DATA_SOURCE_DIRECTORY" ]]; then
    fail_noexit "$DATA_SOURCE_DIRECTORY does not exist"
    echo "Please check your input and make sure $DATA_SOURCE_DIRECTORY exists and try again" 1>&2
    exit 1
fi
REAL_DIR=$(readlink -f "$DATA_SOURCE_DIRECTORY")
if [[ ! "$DATA_SOURCE_DIRECTORY" == "$REAL_DIR" ]]; then
    warn "$DATA_SOURCE_DIRECTORY is actually $REAL_DIR"
    warn "Will enforce permissions on $REAL_DIR"
    DATA_SOURCE_DIRECTORY="$REAL_DIR"
fi
# This is not comprehensive but should stop most misguided attempts
if [[ "$DATA_SOURCE_DIRECTORY" =~ ^/(bin|boot|dev|etc|lib|lib64|proc|root|run|sbin|srv|sys|tmp|usr|var)?(/.*)?$ ]]; then
    fail_noexit "The data source directory cannot be (under) a system directory"
    echo "The data source directory should exist under /mnt, /home, or other non-system directory" 1>&2
    exit 1
fi
echo

# Make sure no more user interaction is necessary
DEBIAN_FRONTEND=noninteractive

# Get HTCondor and Ubuntu versions
HTCONDOR_VERSION=8.9
UBUNTU_CODENAME=$(awk -F= '$1=="UBUNTU_CODENAME" { print $2 ;}' /etc/os-release)
echo "This machine is running Ubuntu $UBUNTU_CODENAME."
echo

base_url="https://research.cs.wisc.edu/htcondor/ubuntu"
key_url="${base_url}/HTCondor-Release.gpg.key"
deb_url="${base_url}/${HTCONDOR_VERSION}/${UBUNTU_CODENAME}"

echo "Checking for required tools..."
# Check for existence of gnupg and wget
missing_pkgs=""
command -v wget >&19 2>&19 || {
    echo "wget is missing, will be installed..."
    missing_pkgs="wget $missing_pkgs"
}
command -v gpg >&19 2>&19 || {
    echo "gnupg2 is missing, will be installed..."
    missing_pkgs="gnupg2 $missing_pkgs"
}
if [[ ! -z "$missing_pkgs" ]]; then
    "Installing $missing_pkgs..."
    apt-get -y update >&19 2>&19 || fail "Could not update packages"
    apt-get -y install $missing_pkgs >&19 2>&19 || fail "Could not install missing packages"
fi

echo "Adding the HTCondor $HTCONDOR_VERSION Ubuntu $UBUNTU_CODENAME repository to apt's sources list..."
wget -O - "$key_url" 2>&19 | apt-key add - >&19 2>&19 || fail "Could not add key from $key_url"
grep "$deb_url" /etc/apt/sources.list >&19 2>&19 || (
    echo "deb $deb_url $UBUNTU_CODENAME contrib" >> /etc/apt/sources.list
    echo "deb-src $deb_url $UBUNTU_CODENAME contrib" >> /etc/apt/sources.list
)

echo "Updating apt's list of packages..."
apt-get -y update >&19 2>&19 || fail "Could not update packages"
sleep 2 # Give apt a couple seconds
echo "Installing HTCondor..."
apt-get -y install git libglobus-gss-assist3 htcondor >&19 2>&19 || fail "Could not install HTCondor"

echo "Downloading, modifying, and installing HTCondor configuration..."
tmp_dir="/tmp/install_htcondor-$$"
config_repo="https://github.com/HTPhenotyping/execute_node_config"
mkdir -p "$tmp_dir" || fail "Could not create temporary directory $tmp_dir"
pushd "$tmp_dir" >&19 2>&19 && (
    git clone $config_repo >&19 2>&19 || fail "Could not clone git repo $config_repo"
    sed -i "s/changeme/$CENTRAL_MANAGER/" execute_node_config/config.d/10-CentralManager
    sed -i "s/changeme/$DATA_SOURCE_NAME/" execute_node_config/config.d/20-UniqueName
    mv execute_node_config/config.d/* /etc/condor/config.d/ || fail "Could not install config files from $tmp_dir"
)
popd >&19 2>&19
rm -rf "$tmp_dir" >&19 2>&19 || warn "Could not remove temporary directory $tmp_dir"
mkdir -p /etc/condor/{tokens.d,passwords.d} >&19 2>&19 || fail "Could not create tokens.d and/or passwords.d"
chmod 700 /etc/condor/{tokens.d,passwords.d} >&19 2>&19 || fail "Could not set permissions on tokens.d and/or passwords.d"
chown -R condor:condor /etc/condor/tokens.d >&19 2>&19 || fail "Could not change ownership of tokens.d and/or passwords.d"

echo "Setting HTCondor to automatically run at boot..."
systemctl enable condor.service >&19 2>&19 || fail "Could not enable condor.service"

echo "Starting HTCondor..."
systemctl start condor.service >&19 2>&19 || fail "Could not start condor.service"

echo "Setting permissions on $DATA_SOURCE_DIRECTORY to be readable by HTCondor..."
chmod o+xr "$DATA_SOURCE_DIRECTORY" || fail "Could not set permissions on $DATA_SOURCE_DIRECTORY"
find "$DATA_SOURCE_DIRECTORY" -type d -exec chmod o+rx "{}" \; || fail "Could not set permissions on $DATA_SOURCE_DIRECTORY subdirectories"
find "$DATA_SOURCE_DIRECTORY" -type f -exec chmod o+r "{}" \; || fail "Could not set permissions on $DATA_SOURCE_DIRECTORY files"

echo
echo "Done. A log file was saved to $LOGFILE"
echo "This log file can be safely deleted once HTCondor is confirmed working."
