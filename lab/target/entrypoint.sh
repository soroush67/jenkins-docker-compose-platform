#!/bin/sh
# Install the Jenkins deploy key, start sshd, then hand over to the stock
# dind entrypoint with the socket owned by the docker group (so `deploy`
# can use it without root).
set -e
install -d -m 0700 -o deploy -g docker /home/deploy/.ssh
install -m 0600 -o deploy -g docker /run/deploy_key.pub /home/deploy/.ssh/authorized_keys
/usr/sbin/sshd
exec dockerd-entrypoint.sh dockerd --host=unix:///var/run/docker.sock --group docker
