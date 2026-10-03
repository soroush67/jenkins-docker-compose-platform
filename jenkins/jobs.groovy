// Job DSL, run by Jenkinsfile.sync. Generates the developer-facing jobs.
// Bound variables: SERVICES (List), SERVICE_LINES (List), PIPELINE_REPO,
// PIPELINE_BRANCH, GIT_CRED.

def fromPipelineRepo(String scriptFile) {
    return {
        cpsScm {
            scm {
                git {
                    remote {
                        url(PIPELINE_REPO)
                        credentials(GIT_CRED)
                    }
                    branch("*/${PIPELINE_BRANCH}")
                }
            }
            scriptPath(scriptFile)
            lightweight(true)
        }
    }
}

def serviceList = "Registered services:\n${SERVICE_LINES.join('\n')}"

folder('paas') {
    description('Self-service docker-compose deployments. You can only run these jobs - ' +
                'services, git locations and target hosts are defined by the platform admins.')
}

pipelineJob('paas/deploy-compose') {
    description("Upload a docker-compose.yml for a service. After approval it is committed to the service's " +
                "git repository and deployed to its host.\n\n${serviceList}")
    parameters {
        choiceParam('SERVICE', SERVICES, 'Service to deploy.')
        stashedFile {
            name('COMPOSE_FILE')
            description('Your docker-compose.yml.')
        }
        stringParam('CHANGE_NOTE', '', 'What changed and why (goes into the git commit message).')
    }
    definition fromPipelineRepo('jenkins/Jenkinsfile.deploy')
}

pipelineJob('paas/show-compose') {
    description("Fetch a service's current docker-compose.yml from git and print it in the console output.\n\n${serviceList}")
    parameters {
        choiceParam('SERVICE', SERVICES, 'Service to show.')
    }
    definition fromPipelineRepo('jenkins/Jenkinsfile.show')
}
