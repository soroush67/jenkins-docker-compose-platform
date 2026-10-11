ARG JENKINS_IMAGE=jenkins/jenkins:lts-jdk17
FROM ${JENKINS_IMAGE}
# git is already in the base image - nothing else is needed on the agent.
# Optional Jenkins mirror for networks where updates.jenkins.io/get.jenkins.io
# are unreachable, e.g. --build-arg JENKINS_MIRROR=https://ftp.belnet.be/mirror/jenkins
ARG JENKINS_MIRROR=
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN if [ -n "$JENKINS_MIRROR" ]; then \
        v=$(java -jar /usr/share/jenkins/jenkins.war --version); \
        export JENKINS_UC="$JENKINS_MIRROR/updates/dynamic-stable-$v" \
               JENKINS_PLUGIN_INFO="$JENKINS_MIRROR/updates/current/plugin-versions.json" \
               JENKINS_UC_DOWNLOAD="$JENKINS_MIRROR"; \
    fi; \
    jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY casc.yaml /usr/share/jenkins/ref/casc.yaml
