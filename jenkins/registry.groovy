// Shared helpers, `load`ed by Jenkinsfile.deploy / .show / .sync.
//
// The service registry (services.yaml) lives in the admin-owned config repo
// (PAAS_CONFIG_REPO). It is read fresh on EVERY build - the SERVICE dropdown
// is only a convenience; what a build actually does always comes from the
// registry, never from anything the developer typed.

// Clone/refresh the config repo into _config and return the parsed,
// validated registry: [defaults: [...], services: [name: entry, ...]]
def readRegistry() {
    dir('_config') {
        git url: env.PAAS_CONFIG_REPO, branch: env.PAAS_CONFIG_BRANCH ?: 'main',
            credentialsId: env.PAAS_GIT_CRED, changelog: false, poll: false
    }
    def reg = readYaml(file: '_config/services.yaml') ?: [:]
    if (!(reg.services instanceof Map) || reg.services.isEmpty()) {
        error('services.yaml has no `services:` entries.')
    }
    def defaults = reg.defaults ?: [:]
    def out = [:]
    reg.services.each { name, entry ->
        out[name] = normalize(name.toString(), defaults, entry ?: [:])
    }
    return [defaults: defaults, services: out]
}

// The one entry a build is about. Fails clearly if it was removed from the
// registry after the job's dropdown was generated.
def service(String name) {
    def reg = readRegistry()
    def svc = reg.services[name]
    if (!svc) {
        error("Service '${name}' is not in services.yaml (any more). Ask a platform admin; " +
              "they re-run paas-admin/sync-registry after changing the registry.")
    }
    return svc
}

def normalize(String name, Map defaults, Map entry) {
    if (!(name ==~ /[a-z0-9][a-z0-9_-]{0,62}/)) {
        error("services.yaml: service name '${name}' must match [a-z0-9][a-z0-9_-]* (it becomes the compose project name).")
    }
    def m = [:]
    m.putAll(defaults)
    m.putAll(entry)
    m.name = name
    m.branch = m.branch ?: 'main'
    ['repo', 'path', 'target_host', 'deploy_dir'].each { k ->
        if (!m[k]) error("services.yaml: service '${name}' is missing `${k}`.")
        m[k] = m[k].toString()
    }
    if (m.path.startsWith('/') || m.path.split('/').contains('..')) {
        error("services.yaml: service '${name}': path must be relative to the repo root, without '..' (got '${m.path}').")
    }
    if (!m.deploy_dir.startsWith('/')) {
        error("services.yaml: service '${name}': deploy_dir must be absolute (got '${m.deploy_dir}').")
    }
    if (!(m.approvers instanceof List) || m.approvers.isEmpty()) {
        error("services.yaml: service '${name}' has no approvers (set `approvers:` on it or under `defaults:`).")
    }
    m.approvers = m.approvers.collect { it.toString() }
    m.description = (m.description ?: '').toString()
    return m
}

// Run `body` with git authenticated through GIT_ASKPASS - the token is
// never put in a URL, so it can't end up in .git/config or in `ps`.
def withGitAuth(Closure body) {
    withCredentials([usernamePassword(credentialsId: env.PAAS_GIT_CRED,
                                      usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
        writeFile file: '.git-askpass', text: '#!/bin/sh\ncase "$1" in Username*) echo "$GIT_USER" ;; *) echo "$GIT_TOKEN" ;; esac\n'
        sh 'chmod 0700 .git-askpass'
        withEnv(["GIT_ASKPASS=${pwd()}/.git-askpass", 'GIT_TERMINAL_PROMPT=0']) {
            body()
        }
    }
}

return this
