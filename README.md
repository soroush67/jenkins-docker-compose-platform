# compose-cd

> 📘 راهنمای کامل فارسی: [docs/fa/GUIDE-FA.md](docs/fa/GUIDE-FA.md)

Upload docker-compose files into your CD repository **through Jenkins**,
so developers don't need write access to the repository.

| Job | Who | What |
|-----|-----|------|
| `cd/upload-compose` | developers | Pick one of the compose files that exist in the CD repo (dropdown), **upload** the new version from your laptop, add a note. Jenkins writes it to exactly that path, commits and `git push`es. |
| `cd/show-compose` | developers | Pick a path; Jenkins fetches the file from git and **prints it in the Console Output**, with its last commit. |
| `cd-admin/refresh-paths` | admins (and automatic) | Scans the CD repo for compose files and regenerates the dropdowns. Runs by itself when the repo changes (SCM poll, every ~5 min). |

What happens after the push - deploying - is up to your existing CD.

## How an upload works

```
laptop ──upload──► Jenkins cd/upload-compose
                     │  lock (one upload per repo/branch at a time)
                     │  fresh clone of CD_REPO@CD_BRANCH
                     │  TARGET must still be a compose file in the repo
                     │  file printed in the console
                     │  overwrite TARGET, commit:
                     │     author = Jenkins user id, committer = Jenkins
                     │     "<path>: <note>"  +  Uploaded-by / Jenkins-build
                     └► git push   (rejected? rebase on latest, retry ×3)
```

- **Only existing paths.** The dropdown is built from the repo; the build
  re-checks the path against a fresh clone, so a stale dropdown or a crafted
  request can never create or write any other file. New folders are added to
  the repo by someone with repo access; refresh picks them up.
- Identical file → "nothing to commit", no empty commit.
- Someone pushing straight to the repo meanwhile is fine: the single-file
  commit is rebased on top and pushed again.
- No approval and no validation of the file, by design - it goes straight to
  `CD_BRANCH`. Use branch protection + a bot that is allowed to push, or point
  `CD_BRANCH` at a branch your CD reviews/merges from.
- The token is only used via `GIT_ASKPASS` - never in a URL, `.git/config` or the console.

## Configuration (Jenkins global environment variables)

| Variable | Example | Meaning |
|---|---|---|
| `CD_REPO` | `https://gitlab.example.com/platform/cd.git` | the CD repository |
| `CD_BRANCH` | `main` | branch read from and pushed to |
| `CD_GIT_CRED` | `gitlab-bot` | *Username with password* credential: bot user + token (read + push `CD_REPO`, read the pipeline repo) |
| `CD_PIPELINE_REPO` | `https://gitlab.example.com/platform/compose-cd.git` | where this repo (the Jenkinsfiles) lives |
| `CD_PIPELINE_BRANCH` | `main` | |
| `CD_PATH_REGEX` | *(optional)* `^services/.*(docker-)?compose\.ya?ml$` | which files are offered (grep -E). Default: any `docker-compose.yml/.yaml` or `compose.yml/.yaml` |

## Installing on a real Jenkins

1. Push this repo to your GitLab (the "pipeline repo").
2. A GitLab bot user with a token (`read_repository`, `write_repository`), allowed to push to `CD_BRANCH`.
3. Plugins: see `lab/jenkins/plugins.txt` (role-strategy, file-parameters,
   job-dsl, lockable-resources, pipeline-utility-steps, credentials-binding, git, ...).
   Keep them up to date - building the lab image printed security advisories
   for a couple of transitive plugins (workflow-multibranch, pipeline-groovy-lib).
4. An agent with label `cd` and `git`.
5. The credential and global variables above.
6. Job DSL script security off, or approve the script once after the first refresh run.
7. Authorization (role-strategy): developers get Overall/Read + an item role on
   pattern `cd(/.*)?` with Job/Read and Job/Build only. See `lab/jenkins/casc.yaml`.
8. Create `cd-admin/refresh-paths` (Pipeline from SCM, `jenkins/Jenkinsfile.refresh`),
   admins only, and run it once (this also activates its SCM polling).

## Lab (everything on this machine)

```
lab/up.sh        # GitLab CE 17.10.5 (with platform/cd) + Jenkins; prints logins
tests/e2e.sh     # 45 end-to-end checks through the Jenkins REST API (rerunnable)
lab/down.sh      # stop (--wipe: delete data + secrets)
```

| What | URL | Login |
|------|-----|-------|
| Jenkins | http://localhost:8090 | `admin`, `dev1`, `dev2` - passwords in `lab/secrets/jenkins.env` |
| GitLab | http://localhost:8929 | `root` - password in `lab/.env` |
| CD repo | http://localhost:8929/platform/cd | |

`lab/up.sh` is idempotent and re-pushes `jenkins/` into the lab GitLab, so
rerun it after editing a pipeline. `tests/e2e.sh` covers access control, the
dropdown contents, show, upload (byte-identical file in git, author, commit
message, single commit, other files untouched), identical upload, empty/missing
file, a path outside the list, two simultaneous uploads, a direct push by
someone else, a folder removed from the repo (refused, not re-created) and a
folder added (appears after refresh, upload works). The rebase-and-retry path
after a rejected push was tested separately with the same shell code.
