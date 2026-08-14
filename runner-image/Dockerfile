FROM ubuntu:24.04

# necessary envs
ENV container docker
ARG LC_ALL=C
ARG DEBIAN_FRONTEND=noninteractive

# install systemd and ssh
RUN apt-get update \
    && apt-get install -y apt-utils unminimize \
    && apt-get upgrade -y \
    && echo y | unminimize \
    && apt-get install -y systemd openssh-server ubuntu-minimal net-tools curl vim git bash-completion lsof dnsutils python3-pip tmux jq sqlite3 gh yq\
        && apt-get autoremove -y \
        && apt-get clean

RUN apt-get install -y ca-certificates \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | tee /etc/apt/sources.list.d/docker.list \
    && mkdir -p /etc/docker/ && echo '{"storage-driver":"overlay2"}' > /etc/docker/daemon.json \
    && apt-get update \
    && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# copy startup scripts
COPY vm-startup.sh /etc/vm-startup.sh
COPY startup.service /etc/systemd/system/startup.service

RUN rm -f /lib/systemd/system/sysinit.target.wants/*.mount \
    && systemctl disable networkd-dispatcher.service \
    && systemctl enable ssh \
    && systemctl enable startup.service \
    && usermod -aG docker ubuntu \
    && echo "ubuntu ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ubuntu \
    && mkdir -p /var/lib/systemd/linger && touch /var/lib/systemd/linger/ubuntu

STOPSIGNAL SIGRTMIN+3
WORKDIR /root
# VOLUME ["/sys/fs/cgroup", "/tmp", "/run", "/run/lock"]
CMD ["/sbin/init"]
