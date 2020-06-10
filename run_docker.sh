#!/bin/bash

usage() {
    echo "Usage: $0" 1>&2
    exit 1
}

fail_noexit() {
    echo "ERROR:    $*" 1>&2
}

# Look for persistent data directory
APPDATA="$HOME/.htphenotyping"

# Look for data source directory
if [[ ! -f "$APPDATA/data_source_directory" ]]; then
    fail_noexit "Required file $APPDATA/data_source_directory does not exist"
    echo "You may need to run install_htcondor.sh again"
    exit 1
else
    DATA_SOURCE_DIRECTORY="$(head -n 1 $APPDATA/data_source_directory)"
fi

# Check for required directories
for reqdir in config.d tokens.d; do
    if [[ ! -d "$APPDATA/$reqdir" ]]; then
	fail_noexit "Required directory $APPDATA/$reqdir does not exist"
	echo "You may need to run install_htcondor.sh again"
	exit 1
    fi
done

# Run docker
echo 
echo "Running HTCondor on Docker, serving data out of $DATA_SOURCE_DIRECTORY..."
echo "To stop HTCondor at any time, hit Ctrl+C (or Control+C)"
echo
docker run --rm -it \
       --name htcondor \
       --mount type=bind,source="$DATA_SOURCE_DIRECTORY",target="/mnt/data" \
       --mount type=bind,source="$APPDATA/tokens.d",target="/etc/condor/tokens.d" \
       --mount type=bind,source="$APPDATA/config.d",target="/etc/condor/config.d" \
       htphenotyping/execute:8.9.7-el7
