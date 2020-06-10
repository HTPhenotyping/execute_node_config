FROM htcondor/execute:8.9.7-el7

# install python3 for registration script
RUN yum -y update && yum -y install python3-condor

# remove existing config, will be bind mounted in
RUN rm /etc/condor/config.d/*

# modify start script to not be so verbose
RUN sed -i 's/bash -x/bash/' /start.sh

# copy wrapper script and set it as default cmd
COPY start-wrapper.sh /
ENTRYPOINT ["/bin/bash", "/start-wrapper.sh"]
CMD []
