FROM htcondor/execute:8.9.7-el7

# install python3
RUN yum -y update && yum -y install python3-condor

# remove existing config except for kernel tuning params
RUN mv /etc/condor/config.d/01-misc.conf /tmp/01-misc.conf && \
    rm /etc/condor/config.d/* && \
    mv /tmp/01-misc.conf /etc/condor/config.d/01-misc.conf

# copy config
COPY config.d/* /etc/condor/config.d/

# modify config
RUN sed -i "s/changeme/docker/"    /etc/condor/config.d/21-InstallUser && \
    sed -i "s|changeme|/mnt/data|" /etc/condor/config.d/22-DataDir && \
    sed -i "s/nobody/slot1/"       /etc/condor/config.d/23-SlotUser

# copy wrapper script and set it as default cmd
COPY start-wrapper.sh /
ENTRYPOINT ["/bin/bash", "-x", "/start-wrapper.sh"]
CMD []
