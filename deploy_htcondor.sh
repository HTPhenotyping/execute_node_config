#!/bin/bash
# This script deploys HTCondor according to the config in
# https://github.com/HTPhenotyping/execute_node_config .
# It requires the user supply the central manager hostname
# and a unique name to identify this machine.
# This script must run with root privileges as it installs
# many packages and modifies system configuration.

set -e

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <Central Manager Hostname> <Unique Name>"
    exit 1
fi

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root or with sudo"
   exit 1
fi

set -x

CENTRAL_MANAGER=$1
UNIQUE_NAME=$2
HTCONDOR_VERSION=8.9
UBUNTU_CODENAME=$(awk -F= '$1=="UBUNTU_CODENAME" { print $2 ;}' /etc/os-release)

base_url="https://research.cs.wisc.edu/htcondor/ubuntu"
key_url="${base_url}/HTCondor-Release.gpg.key"
deb_url="${base_url}/${HTCONDOR_VERSION}/${UBUNTU_CODENAME}"

wget -O - "$key_url" | apt-key add -
grep "$deb_url" /etc/apt/sources.list || (
    echo "deb $deb_url $UBUNTU_CODENAME contrib" >> /etc/apt/sources.list
    echo "deb-src $deb_url $UBUNTU_CODENAME contrib" >> /etc/apt/sources.list
)
apt-get -y update
apt-get -y install git libglobus-gss-assist3 htcondor

tmp_dir="/tmp/$(basename $0)-$$"
mkdir -p "$tmp_dir"
pushd "$tmp_dir" && (
    git clone https://github.com/HTPhenotyping/execute_node_config
    sed -i "s/changeme/$CENTRAL_MANAGER/" execute_node_config/config.d/10-CentralManager
    sed -i "s/changeme/$UNIQUE_NAME/" execute_node_config/config.d/20-UniqueName
    mv execute_node_config/config.d/* /etc/condor/config.d/
)
popd
rm -rf "$tmp_dir"
mkdir -p /etc/condor/{tokens.d,passwords.d}
chmod 700 /etc/condor/{tokens.d,passwords.d}
chown -R condor /etc/condor/tokens.d

systemctl enable condor.service
systemctl start condor.service
