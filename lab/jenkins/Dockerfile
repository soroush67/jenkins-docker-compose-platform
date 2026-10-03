ARG JENKINS_IMAGE=jenkins/jenkins:lts-jdk17
FROM ${JENKINS_IMAGE}
USER root
# git is in the base image; ansible + ssh for the deploy step.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ansible openssh-client \
 && rm -rf /var/lib/apt/lists/*
USER jenkins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY casc.yaml /usr/share/jenkins/ref/casc.yaml
