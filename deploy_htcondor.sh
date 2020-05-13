#!/bin/bash
# This script deploys HTCondor according to the config in
# https://github.com/HTPhenotyping/execute_node_config .
# It requires the user supply the central manager hostname
# and a unique name to identify this machine.
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
LOGFILE="/tmp/deploy_htcondor.$$.log"
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

# Check for data source name
while [ -z "$DATA_SOURCE_NAME" ]; do
    read -p "Preferred data source name (e.g. MyUniversity_Smith): " DATA_SOURCE_NAME
done

# Check for data source directory
while [ -z "$DATA_SOURCE_DIRECTORY" ]; do
    read -p "Data source directory (e.g. /mnt/external/images): " DATA_SOURCE_DIRECTORY
done

# Check data source directory existence
if [[ ! -d "$DATA_SOURCE_DIRECTORY" ]]; then
    fail "$DATA_SOURCE_DIRECTORY does not exist"
fi

# Get HTCondor and Ubuntu versions
HTCONDOR_VERSION=8.9
UBUNTU_CODENAME=$(awk -F= '$1=="UBUNTU_CODENAME" { print $2 ;}' /etc/os-release)
echo "This machine is running Ubuntu $UBUNTU_CODENAME."

base_url="https://research.cs.wisc.edu/htcondor/ubuntu"
key_url="${base_url}/HTCondor-Release.gpg.key"
deb_url="${base_url}/${HTCONDOR_VERSION}/${UBUNTU_CODENAME}"

echo "Adding the HTCondor $HTCONDOR_VERSION Ubuntu $UBUNTU_CODENAME repository to apt's sources list..."
wget -O - "$key_url" 2>&19 | apt-key add - >&19 2>&19 || fail "Could not add key from $key_url"
grep "$deb_url" /etc/apt/sources.list >&19 2>&19 || (
    echo "deb $deb_url $UBUNTU_CODENAME contrib" >> /etc/apt/sources.list
    echo "deb-src $deb_url $UBUNTU_CODENAME contrib" >> /etc/apt/sources.list
)
echo "Updating apt's list of packages..."
apt-get -y update  >&19 2>&19 || fail "Could not update packages"
sleep 1 # Give apt a second
echo "Installing HTCondor..."
apt-get -y install git libglobus-gss-assist3 htcondor >&19 2>&19 || fail "Could not install HTCondor"

tmp_dir="/tmp/$(basename $0)-$$"
config_repo="https://github.com/HTPhenotyping/execute_node_config"
echo "Downloading, modifying, and installing HTCondor configuration"
mkdir -p "$tmp_dir" || fail "Could not create temporary directory $tmp_dir"
pushd "$tmp_dir" >&19 2>&19 && (
    git clone $config_repo >&19 2>&19 || fail "Could not clone git repo $config_repo"
    sed -i "s/changeme/$CENTRAL_MANAGER/" execute_node_config/config.d/10-CentralManager
    sed -i "s/changeme/$DATA_SOURCE_NAME/" execute_node_config/config.d/20-UniqueName
    mv execute_node_config/config.d/* /etc/condor/config.d/ || fail "Could not install config files from $tmp_dir"
)
popd >&19 2>&19
rm -rf "$tmp_dir" >&19 2>&19 || warn "Could not remove $tmp_dir"
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

echo "Done. A log file was saved to $LOGFILE and can be safely deleted once HTCondor is confirmed working."
