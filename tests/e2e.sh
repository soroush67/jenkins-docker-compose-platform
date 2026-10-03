#!/usr/bin/env bash
# End-to-end test against the running lab (lab/up.sh first). Drives Jenkins
# over its REST API as the real lab users, so permission checks are real.
# Deploys to the lab target and checks the result in GitLab and over HTTP.
set -uo pipefail
cd "$(dirname "$0")"
LAB=../lab
. "$LAB/lib.sh"
set -a; . "$LAB/secrets/jenkins.env"; set +a
BOT_TOKEN=$(cat "$LAB/secrets/gitlab-bot-token")
FX=fixtures
DEPLOY=paas/deploy-compose
SHOW=paas/show-compose

pass=0; fail=0
ok()   { echo "  PASS  $*"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $*"; fail=$((fail+1)); }
check() { local desc=$1; shift; if "$@"; then ok "$desc"; else bad "$desc"; fi; }
as() { case $1 in
        admin) j_login admin "$JENKINS_ADMIN_PASSWORD" ;;
        approver1) j_login approver1 "$JENKINS_APPROVER1_PASSWORD" ;;
        dev1) j_login dev1 "$JENKINS_DEV1_PASSWORD" ;;
        dev2) j_login dev2 "$JENKINS_DEV2_PASSWORD" ;;
       esac; }
http_body() { curl -fsS --max-time 5 "$1" 2>/dev/null; }
gitlab_last_commit() {  # <project> <path>
    curl -fsS -H "PRIVATE-TOKEN: $BOT_TOKEN" \
      "http://localhost:8929/api/v4/projects/platform%2F$1/repository/commits?ref_name=main&path=$2&per_page=1" \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["id"]+"\n"+d[0]["message"] if d else "")'
}
# deploy <user> <service> <fixture> <note> -> echoes build number
deploy() { as "$1"; j_trigger "$DEPLOY" -F "SERVICE=$2" -F "COMPOSE_FILE=@$FX/$3" -F "CHANGE_NOTE=$4"; }

echo "== 1. access control (dev1)"
as dev1
check "dev1 cannot see paas-admin"             [ "$(j_status /job/paas-admin/)" != 200 ]
check "dev1 cannot open job configuration"     [ "$(j_status /job/paas/job/deploy-compose/configure)" = 403 ]
check "dev1 cannot open Manage Jenkins"        [ "$(j_status /manage/)" = 403 ]
check "dev1 cannot browse the job workspace"   [ "$(j_status /job/paas/job/deploy-compose/ws/)" != 200 ]
check "dev1 cannot see credentials"            [ "$(j_status /manage/credentials/)" = 403 ]
check "dev1 can see the deploy job"            [ "$(j_status /job/paas/job/deploy-compose/)" = 200 ]
cannot_trigger() { ! j_trigger "$1" >/dev/null 2>&1; }
check "dev1 cannot trigger sync-registry"      cannot_trigger paas-admin/sync-registry

echo "== 2. show before anything was deployed"
as dev1; n=$(j_trigger "$SHOW" -F SERVICE=hello-web); r=$(j_wait "$SHOW" "$n")
check "show-compose (empty repo) is UNSTABLE"  [ "$r" = UNSTABLE ]
check "...and says nothing is there yet"       grep -q 'No docker-compose.yml yet' <(j_console "$SHOW" "$n")

echo "== 3. dev1 deploys hello-web v1, approver1 approves"
n=$(deploy dev1 hello-web hello-v1.yml "first version")
id=$(j_wait_input "$DEPLOY" "$n")
check "build waits for approval"               [ -n "$id" ]
check "console shows the uploaded file"        grep -q "hello-web v1" <(j_console "$DEPLOY" "$n")
as dev1; code=$(j_approve "$DEPLOY" "$n" "$id")
check "dev1 cannot approve own deploy (HTTP $code)" [ "$code" != 200 ]
check "...build is still waiting"              [ "$(j_result "$DEPLOY" "$n")" = "" ]
as dev2; code=$(j_approve "$DEPLOY" "$n" "$id")
check "dev2 (not an approver) cannot approve (HTTP $code)" [ "$code" != 200 ] 
check "...build is still waiting"              [ "$(j_result "$DEPLOY" "$n")" = "" ]
as approver1; j_approve "$DEPLOY" "$n" "$id" >/dev/null
r=$(j_wait "$DEPLOY" "$n")
check "deploy SUCCESS after approval"          [ "$r" = SUCCESS ]
[ "$r" = SUCCESS ] || j_console "$DEPLOY" "$n" | tail -40
check "app serves v1"                          grep -q 'hello-web v1' <(http_body http://localhost:18080)
c=$(gitlab_last_commit hello-web-deploy deploy/docker-compose.yml)
check "commit in GitLab at deploy/docker-compose.yml" [ -n "$c" ]
check "...with Requested-by: dev1"             grep -q 'Requested-by: dev1' <<<"$c"
check "...with Approved-by: approver1"         grep -q 'Approved-by: approver1' <<<"$c"
sha=$(head -1 <<<"$c")
check "target records the deployed commit"     grep -q "$sha" <(docker exec cp-target cat /opt/apps/hello-web/.compose-paas.json)

echo "== 4. dev2 reads it back through show-compose"
as dev2; n=$(j_trigger "$SHOW" -F SERVICE=hello-web); r=$(j_wait "$SHOW" "$n")
check "show-compose SUCCESS"                   [ "$r" = SUCCESS ]
check "console prints the file from git"       grep -q 'hello-web v1' <(j_console "$SHOW" "$n")
check "console prints the last change"         grep -q "${sha:0:7}" <(j_console "$SHOW" "$n")

echo "== 5. v2 rejected -> nothing changes"
n=$(deploy dev1 hello-web hello-v2.yml "second version"); id=$(j_wait_input "$DEPLOY" "$n")
as approver1; j_reject "$DEPLOY" "$n" "$id" >/dev/null; r=$(j_wait "$DEPLOY" "$n")
check "rejected deploy is ABORTED"             [ "$r" = ABORTED ]
check "app still serves v1"                    grep -q 'hello-web v1' <(http_body http://localhost:18080)
check "git unchanged"                          [ "$(head -1 <<<"$(gitlab_last_commit hello-web-deploy deploy/docker-compose.yml)")" = "$sha" ]

echo "== 6. v2 approved"
n=$(deploy dev1 hello-web hello-v2.yml "second version"); id=$(j_wait_input "$DEPLOY" "$n")
as approver1; j_approve "$DEPLOY" "$n" "$id" >/dev/null; r=$(j_wait "$DEPLOY" "$n")
check "deploy v2 SUCCESS"                      [ "$r" = SUCCESS ]
check "app serves v2"                          grep -q 'hello-web v2' <(http_body http://localhost:18080)

echo "== 7. same file again -> nothing to commit, still redeploys"
n=$(deploy dev2 hello-web hello-v2.yml "no-op"); id=$(j_wait_input "$DEPLOY" "$n")
as approver1; j_approve "$DEPLOY" "$n" "$id" >/dev/null; r=$(j_wait "$DEPLOY" "$n")
check "no-op deploy SUCCESS"                   [ "$r" = SUCCESS ]
check "...says nothing to commit"              grep -q 'nothing to commit' <(j_console "$DEPLOY" "$n")

echo "== 8. self-approval is impossible"
n=$(deploy approver1 whoami whoami.yml "approver deploys"); r=$(j_wait "$DEPLOY" "$n")
check "only approver requests -> FAILURE (no one else may approve)" [ "$r" = FAILURE ]
check "...with a clear message"                grep -q 'No approver other than approver1' <(j_console "$DEPLOY" "$n")
n=$(deploy admin hello-web hello-v2.yml "admin self-approve"); id=$(j_wait_input "$DEPLOY" "$n")
as admin; j_approve "$DEPLOY" "$n" "$id" >/dev/null; r=$(j_wait "$DEPLOY" "$n")
check "admin approving own request -> FAILURE" [ "$r" = FAILURE ]
check "...cannot approve message"              grep -q 'cannot approve it' <(j_console "$DEPLOY" "$n")

echo "== 9. second service (whoami): dev2 deploys, approver1 approves"
n=$(deploy dev2 whoami whoami.yml "whoami"); id=$(j_wait_input "$DEPLOY" "$n")
as approver1; j_approve "$DEPLOY" "$n" "$id" >/dev/null; r=$(j_wait "$DEPLOY" "$n")
check "whoami deploy SUCCESS"                  [ "$r" = SUCCESS ]
check "whoami answers"                         grep -q 'Hostname' <(http_body http://localhost:18081)
check "committed at compose/production/docker-compose.yml" [ -n "$(gitlab_last_commit whoami-deploy compose/production/docker-compose.yml)" ]

echo "== 10. broken compose fails the deploy"
printf 'services:\n  web:\n    image: nginx:1.27-alpine\n    command: ["sh","-c","exit 3"]\n    ports: ["18082:80"]\n' > /tmp/broken-compose-$$.yml
cp /tmp/broken-compose-$$.yml "$FX/.broken.yml"
n=$(deploy dev1 whoami .broken.yml "crashing container"); id=$(j_wait_input "$DEPLOY" "$n")
as approver1; j_approve "$DEPLOY" "$n" "$id" >/dev/null; r=$(j_wait "$DEPLOY" "$n")
check "crashing container -> deploy FAILURE (compose up --wait)" [ "$r" = FAILURE ]
rm -f "$FX/.broken.yml" /tmp/broken-compose-$$.yml
# leave whoami in a good state again
n=$(deploy dev2 whoami whoami.yml "restore whoami"); id=$(j_wait_input "$DEPLOY" "$n")
as approver1; j_approve "$DEPLOY" "$n" "$id" >/dev/null; r=$(j_wait "$DEPLOY" "$n")
check "whoami restored"                        [ "$r" = SUCCESS ]

echo
echo "== $pass passed, $fail failed"
[ "$fail" = 0 ]
