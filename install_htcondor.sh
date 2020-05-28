#!/bin/bash
# This script deploys HTCondor according to the configs in
# https://github.com/HTPhenotyping/execute_node_config .
# It requires the user supply the central manager hostname,
# a unique name to identify this machine, and the path that
# users are expected to transfer data from.
# This script will ask for sudo privileges as it installs
# many packages and modifies system configuration.

usage() {
    echo "Usage: $0 -c <Central Manager Hostname> -d <Data Source Directory> -n <Data Source Name> -p <Project Name>" 1>&2
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
	p)
	    PROJECT="$OPTARG"
	    ;;
	\?)
	    usage
	    ;;
    esac
done

echo

# Set up logging https://askubuntu.com/a/1001404
LOGFILE="/tmp/install_htcondor.$$.log"
exec 19> $LOGFILE
BASH_XTRACEFD=19
set -x

# Check for root
SUDO=""
if [ "$(id -u)" != "0" ]; then
    SUDO="sudo"
fi

# Set defaults
DEFAULT_PROJECT="drone"
if [[ -z "$PROJECT" ]]; then
    PROJECT="$DEFAULT_PROJECT"
fi

case "$PROJECT" in
    'drone')
	DEFAULT_CENTRAL_MANAGER="htpheno-cm.chtc.wisc.edu"
	DEFAULT_DATA_SOURCE_DIRECTORY="$(readlink -m "$HOME/${PROJECT}_data")"
	;;
    *)
	DEFAULT_CENTRAL_MANAGER="htpheno-cm.chtc.wisc.edu"
	DEFAULT_DATA_SOURCE_DIRECTORY="$(readlink -m "$HOME/data")"
	;;
esac

DEFAULTS_FILE="$HOME/.htpheno_defaults"
if [[ -f "$DEFAULTS_FILE" ]]; then
    source "$DEFAULTS_FILE"
fi

# If input is needed, let the user know that they can accept defaults
if [[ -z "$CENTRAL_MANAGER" || -z "$DATA_SOURCE_NAME" || -z "$DATA_SOURCE_DIRECTORY" ]]; then
    echo
    echo "Respond to the following prompts following the installation page and using"
    echo "  the data you entered during registration."
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
    fail_noexit "The central manager hostname must be a valid hostname"
    echo "Please check your input and try again" 1>&2
    exit 1
fi
echo "DEFAULT_CENTRAL_MANAGER=\"$CENTRAL_MANAGER\"" > $DEFAULTS_FILE

# Check for data source name
while [[ -z "$DATA_SOURCE_NAME" ]]; do
    read -p "Preferred data source name [$DEFAULT_DATA_SOURCE_NAME]: " DATA_SOURCE_NAME
    [[ -z "$DATA_SOURCE_NAME" ]] && [[ ! -z "$DEFAULT_DATA_SOURCE_NAME" ]] && \
	DATA_SOURCE_NAME="$DEFAULT_DATA_SOURCE_NAME"
done
if [[ ! "$DATA_SOURCE_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
    fail_noexit "The data source name may only contain alphanumeric characters and underscores"
    echo "Please check your input and try again" 1>&2
    exit 1
fi
echo "DEFAULT_DATA_SOURCE_NAME=\"$DATA_SOURCE_NAME\"" >> $DEFAULTS_FILE

# Check for data source directory
while [[ -z "$DATA_SOURCE_DIRECTORY" ]]; do
    read -p "Data source directory [$DEFAULT_DATA_SOURCE_DIRECTORY]: " DATA_SOURCE_DIRECTORY
    [[ -z "$DATA_SOURCE_DIRECTORY" ]] && [[ ! -z "$DEFAULT_DATA_SOURCE_DIRECTORY" ]] && \
	DATA_SOURCE_DIRECTORY="$DEFAULT_DATA_SOURCE_DIRECTORY"
done

# Run tests on directory
if [[ ! "$DATA_SOURCE_DIRECTORY" =~ ^/ ]]; then
    fail_noexit "The data source directory must be an absolute path"
    echo "The data source directory must be the full path, starting with /" 1>&2
    exit 1
fi
REAL_DIR=$(readlink -m "$DATA_SOURCE_DIRECTORY")
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
if [[ ! -d "$DATA_SOURCE_DIRECTORY" ]]; then
    warn "$DATA_SOURCE_DIRECTORY does not exist, attempting to create it..."
    mkdir -pv "$DATA_SOURCE_DIRECTORY" >&19 2>&19 || fail "Could not create $DATA_SOURCE_DIRECTORY"
    echo "Created $DATA_SOURCE_DIRECTORY..."
fi
echo "DEFAULT_DATA_SOURCE_DIRECTORY=\"$DATA_SOURCE_DIRECTORY\"" >> $DEFAULTS_FILE
echo

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
    echo "Installing $missing_pkgs..."
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get -y update >&19 2>&19 || fail "Could not update packages"
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get -y install $missing_pkgs >&19 2>&19 || fail "Could not install missing packages"
fi

echo "Adding the HTCondor $HTCONDOR_VERSION Ubuntu $UBUNTU_CODENAME repository to apt's sources list..."
wget -O - "$key_url" 2>&19 | $SUDO apt-key add - >&19 2>&19 || fail "Could not add key from $key_url"
grep "$deb_url" /etc/apt/sources.list >&19 2>&19 || (
    echo "deb $deb_url $UBUNTU_CODENAME contrib" | $SUDO tee -a /etc/apt/sources.list > /dev/null
    echo "deb-src $deb_url $UBUNTU_CODENAME contrib" | $SUDO tee -a /etc/apt/sources.list > /dev/null
)

echo "Updating apt's list of packages..."
DEBIAN_FRONTEND=noninteractive $SUDO apt-get -y update >&19 2>&19 || fail "Could not update packages"
sleep 2 # Give apt a couple seconds
echo "Installing HTCondor (this may take 1 to 2 minutes)..."
DEBIAN_FRONTEND=noninteractive $SUDO apt-get -y install git libglobus-gss-assist3 htcondor >&19 2>&19 || fail "Could not install HTCondor"

echo "Downloading, modifying, and installing HTCondor configuration..."
tmp_dir="/tmp/install_htcondor-$$"
config_repo="https://github.com/HTPhenotyping/execute_node_config"
mkdir -p "$tmp_dir" || fail "Could not create temporary directory $tmp_dir"
pushd "$tmp_dir" >&19 2>&19 && (
    git clone $config_repo >&19 2>&19 || fail "Could not clone git repo $config_repo"
    sed -i "s/changeme/$CENTRAL_MANAGER/"       execute_node_config/config.d/10-CentralManager
    sed -i "s/changeme/$DATA_SOURCE_NAME/"      execute_node_config/config.d/20-UniqueName
    sed -i "s/changeme/$USER/"                  execute_node_config/config.d/21-InstallUser
    sed -i "s|changeme|$DATA_SOURCE_DIRECTORY|" execute_node_config/config.d/22-DataDir
    $SUDO mv execute_node_config/config.d/* /etc/condor/config.d/ || fail "Could not install config files from $tmp_dir"
)
popd >&19 2>&19
rm -rf "$tmp_dir" >&19 2>&19 || warn "Could not remove temporary directory $tmp_dir"
$SUDO mkdir -p /etc/condor/{tokens.d,passwords.d}  >&19 2>&19 || fail "Could not create tokens.d and/or passwords.d"
$SUDO chmod 700 /etc/condor/{tokens.d,passwords.d} >&19 2>&19 || fail "Could not set permissions on tokens.d and/or passwords.d"
$SUDO chown -R condor:condor /etc/condor/tokens.d  >&19 2>&19 || fail "Could not change ownership of tokens.d and/or passwords.d"

pidof systemd >&19 2>&19 && {
    echo "Setting HTCondor to automatically run at boot..."
    $SUDO systemctl enable condor.service >&19 2>&19 || fail "Could not enable condor.service"
}

echo "Starting HTCondor..."
pidof systemd >&19 2>&19 && {
    $SUDO systemctl start condor.service >&19 2>&19 || fail "Could not start condor.service"
} || {
    $SUDO condor_master >&19 2>&19 || fail "Could not start condor_master"
}

echo "Setting permissions on $DATA_SOURCE_DIRECTORY to be readable by HTCondor..."
$SUDO chmod o+xr "$DATA_SOURCE_DIRECTORY" || fail "Could not set permissions on $DATA_SOURCE_DIRECTORY"
$SUDO find "$DATA_SOURCE_DIRECTORY" -type d -exec chmod o+rx "{}" \; || fail "Could not set permissions on $DATA_SOURCE_DIRECTORY subdirectories"
$SUDO find "$DATA_SOURCE_DIRECTORY" -type f -exec chmod o+r "{}" \; || fail "Could not set permissions on $DATA_SOURCE_DIRECTORY files"

# Create a symlink to the data source directory on the Desktop
if [[ -d "$HOME/Desktop" ]]; then
    echo "Creating a link to $DATA_SOURCE_DIRECTORY on the Desktop..."
    ln -sfT "$DATA_SOURCE_DIRECTORY" "$HOME/Desktop/$(basename "$DATA_SOURCE_DIRECTORY")" >&19 2>&19 || \
	warn "Could not create link to $DATA_SOURCE_DIRECTORY on the Desktop"
fi

echo
echo "Finishing data source $DATA_SOURCE_NAME registration with $CENTRAL_MANAGER..."
echo
# Using register.py from master:
# https://github.com/HTPhenotyping/registration/blob/master/register.py
register_url="https://raw.githubusercontent.com/HTPhenotyping/registration/master/register.py"
register_path="/usr/sbin/register.py"
$SUDO wget "$register_url" -O "$register_path" >&19 2>&19 || fail "Could not download register.py"
$SUDO chmod u+x "$register_path" || fail "Could not set permissions on register.py"
regcmd="register.py --pool=$CENTRAL_MANAGER --source=$DATA_SOURCE_NAME"
$SUDO $regcmd && {
    $SUDO condor_status -limit 1 >&19 2>&19 || {
	echo
	warn "Registration completed, but the machine could not talk to the central manager"
	echo "Please email the HTPhenotyping service providers with your data source name ($DATA_SOURCE_NAME)" 1>&2
	echo "and let them know about this message. If possible, include the contents of $LOGFILE" 1>&2
    }
} || {
    echo
    warn "Could not finish registration at this time."
    echo "You can retry registration at a later time by running:" 1>&2
    echo "  $SUDO $regcmd" 1>&2
}

echo
echo "Done. A log file was saved to $LOGFILE"
echo "This log file can be safely deleted once HTCondor is confirmed working."
echo
