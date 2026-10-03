// Shared helpers, `load`ed by Jenkinsfile.upload / .show / .refresh.
//
// Configuration (Jenkins global environment variables):
//   CD_REPO          the CD repository (HTTP(S) URL)
//   CD_BRANCH        branch to read from / push to (default main)
//   CD_GIT_CRED      username+token credential that can read and push CD_REPO
//   CD_PATH_REGEX    which files count as compose files (grep -E, default below)

def branch()    { return env.CD_BRANCH ?: 'main' }
def pathRegex() { return env.CD_PATH_REGEX ?: '(^|/)(docker-)?compose\\.ya?ml$' }

// Run `body` with git authenticated through GIT_ASKPASS - the token is never
// put in a URL, so it can't end up in .git/config, the console or `ps`.
def withGitAuth(Closure body) {
    withCredentials([usernamePassword(credentialsId: env.CD_GIT_CRED,
                                      usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
        writeFile file: '.git-askpass', text: '#!/bin/sh\ncase "$1" in Username*) echo "$GIT_USER" ;; *) echo "$GIT_TOKEN" ;; esac\n'
        sh 'chmod 0700 .git-askpass'
        withEnv(["GIT_ASKPASS=${pwd()}/.git-askpass", 'GIT_TERMINAL_PROMPT=0']) {
            body()
        }
    }
}

// Fresh clone of CD_REPO@branch into `dirName`.
def cloneRepo(String dirName) {
    withEnv(["CLONE_DIR=${dirName}", "CLONE_BRANCH=${branch()}"]) {
        withGitAuth {
            sh '''
                set -eu
                rm -rf "$CLONE_DIR"
                git clone -q --branch "$CLONE_BRANCH" "$CD_REPO" "$CLONE_DIR"
            '''
        }
    }
}

// Compose files tracked in the clone at `dirName`, sorted.
def composePaths(String dirName) {
    def out = ''
    withEnv(["CLONE_DIR=${dirName}", "CD_PATH_REGEX=${pathRegex()}"]) {
        out = sh(returnStdout: true,
                 script: 'git -C "$CLONE_DIR" ls-files | grep -E "$CD_PATH_REGEX" | LC_ALL=C sort || true').trim()
    }
    return out ? out.split('\n').toList() : []
}

// Web link to a commit, for GitLab/GitHub-style URLs (best effort).
def commitUrl(String sha) {
    def base = env.CD_REPO.replaceAll(/\.git$/, '')
    return base.contains('github.com') ? "${base}/commit/${sha}" : "${base}/-/commit/${sha}"
}

// The exact path the user picked must still be a compose file in the repo:
// the dropdown can be stale, and the upload must never create new paths.
def requireComposePath(String dirName, String target) {
    if (!target) {
        error('No TARGET selected.')
    }
    def paths = composePaths(dirName)
    if (!paths.contains(target)) {
        error("'${target}' is not an existing compose file in ${env.CD_REPO} (${branch()}) any more. " +
              "The list may be out of date - ask an admin to run cd-admin/refresh-paths.")
    }
}

return this
