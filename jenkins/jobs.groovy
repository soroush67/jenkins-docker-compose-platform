// Job DSL, run by Jenkinsfile.refresh. Generates the developer-facing jobs.
// Bound variables: PATHS (List), CD_REPO, CD_BRANCH, PIPELINE_REPO,
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

def repoLine = "CD repository: ${CD_REPO} (branch ${CD_BRANCH})"

folder('cd') {
    description("docker-compose files of the CD repository. ${repoLine}")
}

pipelineJob('cd/upload-compose') {
    description("Upload a docker-compose.yml from your machine. Jenkins writes it to the selected path " +
                "in the CD repository and pushes it.\n${repoLine}")
    parameters {
        choiceParam('TARGET', PATHS, 'Which compose file in the repository to replace.')
        stashedFile {
            name('COMPOSE_FILE')
            description('The docker-compose.yml from your machine.')
        }
        stringParam('CHANGE_NOTE', '', 'What changed and why (goes into the git commit message).')
    }
    definition fromPipelineRepo('jenkins/Jenkinsfile.upload')
}

pipelineJob('cd/show-compose') {
    description("Fetch a compose file from the CD repository and print it in the console output.\n${repoLine}")
    parameters {
        choiceParam('TARGET', PATHS, 'Which compose file to show.')
    }
    definition fromPipelineRepo('jenkins/Jenkinsfile.show')
}
