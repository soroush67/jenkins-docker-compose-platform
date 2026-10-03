ARG JENKINS_IMAGE=jenkins/jenkins:lts-jdk17
FROM ${JENKINS_IMAGE}
# git is already in the base image - nothing else is needed on the agent.
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY casc.yaml /usr/share/jenkins/ref/casc.yaml
