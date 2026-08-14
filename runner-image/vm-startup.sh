#!/bin/bash

# Create ubuntu home
! test -d /home/ubuntu && mkdir /home/ubuntu

# Setup permissions
chown ubuntu:ubuntu /opt \
    /home/ubuntu \
    /home/ubuntu/{.bashrc,.profile,.tmux.conf}

chown -R ubuntu:ubuntu /home/ubuntu/.ssh

