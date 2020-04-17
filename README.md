# HTPhenology Execute Node Configuration

1. Install HTCondor
2. Copy configuration from this repo's `config.d/` directory into `/etc/condor/config.d/`
3. Modify configuration, make sure that `CONDOR_HOST` points to your central manager in `10-CentralManager`,
and make sure that `UniqueName` is set to something unique like `"MyNode0001"` in `20-UniqueName`
4. Obtain a token from from your central manager containing the `ADVERTISE_STARTD` and `ADVERTISE_MASTER` authorizations and place it in `/etc/condor/tokens.d`
5. Enable the condor service to run at boot

## Install HTCondor

Modify the following for the distro/version of Linux running:

    wget https://research.cs.wisc.edu/htcondor/ubuntu/HTCondor-Release.gpg.key
    apt-key add HTCondor-Release.gpg.key
    echo "deb http://research.cs.wisc.edu/htcondor/ubuntu/8.9/xenial xenial contrib" >> /etc/apt/sources.list
    echo "deb-src http://research.cs.wisc.edu/htcondor/ubuntu/8.9/xenial xenial contrib" >> /etc/apt/sources.list
    apt-get update
    apt-get install git libglobus-gss-assist3 htcondor

## Copy configuration

    git clone https://github.com/HTPhenotyping/execute_node_config
    cp execute_node_config/config.d/* /etc/condor/config.d/
    mkdir /etc/condor/{tokens.d,passwords.d}

## Modify configuration

Get the hostname of your central manager (e.g. "my-cm-host") and determine a unique name
for your execute node (e.g. "MyNode0001"). Then edit the config by hand:

    nano /etc/condor/config.d/10-CentralManager
    nano /etc/condor/config.d/20-UniqueName

or make the changes on the command line:

    sed -i 's/changeme/my-cm-host/' /etc/condor/config.d/10-CentralManager
    sed -i 's/changeme/MyNode0001/' /etc/condor/config.d/20-UniqueName

## Obtain token
### On central manager

If the group this execute node belongs to does not already have a (revokable) password already:

    condor_store_credd -f /etc/condor/passwords.d/GROUPNAME
    <generate 64-char password from https://passwordsgenerator.net/>

Then:

    condor_token_create -authz ADVERTISE_STARTD -authz ADVERTISE_MASTER -identity STARTD_MyNode0001@my-cm-host -key GROUPNAME > /etc/condor/.created_tokens/MyNode0001.key

### On execute node

    scp $(condor_config_val CONDOR_HOST):/etc/condor/.created_tokens/MyNode0001.key /etc/condor/tokens.d/

## Enable service and start it

    systemctl enable condor.service
    systemctl start condor.service
