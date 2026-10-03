# compose-paas

> 📘 راهنمای کامل فارسی (توسعه‌دهنده، تأییدکننده، ادمین): [docs/fa/GUIDE-FA.md](docs/fa/GUIDE-FA.md)

Jenkins as a small "platform as a service" for docker-compose apps.
Developers get two buttons and nothing else:

| Job | Who | What |
|-----|-----|------|
| `paas/deploy-compose` | developers | Pick a service, **upload a docker-compose.yml**, add a note. An approver approves; Jenkins commits the file to the service's git repo/path and deploys that commit to the service's host. |
| `paas/show-compose`   | developers | Pick a service; Jenkins fetches its docker-compose.yml from git and **prints it in the Console Output** (with the last commit). |
| `paas-admin/sync-registry` | admins only | Validates `services.yaml` and regenerates the two jobs above (the SERVICE dropdown). |

Developers never get write access to the deployment repos, the servers, or
Jenkins job configuration - only the Jenkins bot account can push, and only
Jenkins holds the SSH deploy key.

## How a deploy works

```
dev uploads file ──► Request: registry lookup, file printed in console
                 ──► Approval: input step, submitters = service's approvers minus the requester
                         (rejected → ABORTED, nothing touched)
                 ──► Commit & deploy (lock per service):
                       clone repo → write <path> → commit (author = requester,
                       Requested-by / Approved-by / Jenkins-build trailers) → push
                       ansible: copy that commit's file to <deploy_dir>,
                       docker compose -p <service> up -d --remove-orphans --wait
```

- What a build does always comes from `services.yaml`, read fresh from the
  config repo on every build. The developer only picks a name.
- **No self-approval**: the requester is removed from the submitter list. Jenkins
  admins can approve any input, so the pipeline also fails the build if
  approver == requester.
- Waiting for approval holds no executor (`agent none` stage), times out after 24h.
- Same file as in git → "nothing to commit", it is redeployed as is.
- `--wait` makes a crash-looping container fail the deploy instead of reporting success.
- The target gets `<deploy_dir>/.compose-paas.json` (commit, requester, approver, build URL).
- Order is commit → deploy. If the deploy fails, the commit stays in git and the
  build is red; fix and deploy again.

## Service registry (`services.yaml`, admin-owned config repo)

```yaml
defaults:
  branch: main
  approvers: [team-lead, platform-admin]   # Jenkins user ids
services:
  hello-web:
    description: "Static hello page"
    repo: https://gitlab.example.com/platform/hello-web-deploy.git
    path: deploy/docker-compose.yml          # where in the repo
    target_host: app-server-01.example.com   # SSH as PAAS_SSH_CRED's user
    deploy_dir: /opt/apps/hello-web
    approvers: [team-lead]                   # optional per-service override
```

See `config-example/services.yaml`. After editing it, run `paas-admin/sync-registry`.

## Installing on a real Jenkins

1. Push this repo to your GitLab (it is the "pipeline repo").
2. Create a config repo containing `services.yaml`. Only admins get write access to it.
3. Plugins: see `lab/jenkins/plugins.txt` (role-strategy, file-parameters,
   job-dsl, lockable-resources, pipeline-utility-steps, ...).
4. Agent with label `paas`: git, ansible, ssh client.
5. Global env vars: `PAAS_CONFIG_REPO`, `PAAS_CONFIG_BRANCH`, `PAAS_PIPELINE_REPO`,
   `PAAS_PIPELINE_BRANCH`, `PAAS_GIT_CRED`, `PAAS_SSH_CRED`, and
   `PAAS_HOST_KEY_CHECKING=True` once the agent's known_hosts is populated.
6. Credentials: `PAAS_GIT_CRED` = username + token of a bot user that can
   read the config/pipeline repos and push to the service repos;
   `PAAS_SSH_CRED` = SSH key of a user in the `docker` group on the target hosts.
7. Job DSL script security off (the sync job is admin-only and runs a
   script from the admin-owned pipeline repo), or approve the script once.
8. Authorization: see `lab/jenkins/casc.yaml` - developers get Overall/Read
   plus Job/Read+Build+Cancel on pattern `paas(/.*)?` only.
9. Create `paas-admin/sync-registry` (Pipeline from SCM, `jenkins/Jenkinsfile.sync`) and run it.

## Lab (everything runs on this machine)

```
lab/up.sh          # GitLab CE 17.10.5 + Jenkins + deploy target; prints logins
tests/e2e.sh       # 40 end-to-end checks through the Jenkins REST API
lab/down.sh        # stop (--wipe: delete data + secrets)
```

| What | URL |
|------|-----|
| Jenkins | http://localhost:8090 (admin, approver1, dev1, dev2 - passwords in `lab/secrets/jenkins.env`) |
| GitLab | http://localhost:8929 (root - password in `lab/.env`) |
| Deployed apps | http://localhost:18080 (hello-web), :18081 (whoami) |

`lab/up.sh` is idempotent and also pushes the current `jenkins/` + `ansible/`
into the lab GitLab, so rerun it after editing a pipeline.

`tests/e2e.sh` covers access control, the full deploy flow (approval, commit
trailers, deployed commit marker, app served over HTTP), show, reject → no
change, no-op redeploy, self-approval for both a sole approver and an admin,
a second service with a different repo path, and a crashing container failing
the deploy.

## Not included (by choice for now)

- No validation or policy on the uploaded file (privileged, host network,
  docker.sock mounts, ...) - the approver is the only gate. Easy to add as a
  stage before Approval.
- No per-service restriction of *which developers* may deploy - every
  developer can request any service; the approvers decide.
- Secrets/.env files for apps are not handled - only docker-compose.yml.
