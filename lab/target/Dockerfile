# Lab deploy target: a Docker host (docker-in-docker) with sshd, a `deploy`
# user in the docker group, key-only login. Python is there for Ansible.
FROM docker:27-dind
# adduser -D leaves the account locked ("!"), which sshd rejects even for
# key logins; "*" in /etc/shadow = no password, but not locked.
RUN set -eux; \
    apk add --no-cache --upgrade openssh-server openssh-client python3 bash; \
    ssh-keygen -A; \
    getent group docker >/dev/null || addgroup -S docker; \
    adduser -D -s /bin/bash -G docker deploy; \
    sed -i 's/^deploy:!/deploy:*/' /etc/shadow; \
    sed -i -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
           -e 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config; \
    mkdir -p /opt/apps; chown deploy:docker /opt/apps
COPY entrypoint.sh /usr/local/bin/target-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/target-entrypoint.sh"]
