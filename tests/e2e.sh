#!/usr/bin/env bash
# End-to-end test against the running lab (lab/up.sh first). Drives Jenkins
# over its REST API as the real lab users (so permission checks are real)
# and checks the result directly in the lab GitLab. Rerunnable: it resets
# the CD repo's files to the seed content first.
set -uo pipefail
cd "$(dirname "$0")"
LAB=../lab
SEED=$LAB/seed/cd
. "$LAB/lib.sh"
set -a; . "$LAB/secrets/jenkins.env"; set +a
GL() { python3 ./gitlab.py "$@"; }
UP=cd/upload-compose
SHOW=cd/show-compose
REFRESH=cd-admin/refresh-paths
PAY=services/payment/docker-compose.yml
ORD=services/orders/docker-compose.yml
MON=infra/monitoring/compose.yaml
NEW=services/billing/docker-compose.yml
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()   { echo "  PASS  $*"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $*"; fail=$((fail+1)); }
check() { local desc=$1; shift; if "$@"; then ok "$desc"; else bad "$desc"; fi; }
as() { case $1 in
        admin) j_login admin "$JENKINS_ADMIN_PASSWORD" ;;
        dev1)  j_login dev1 "$JENKINS_DEV1_PASSWORD" ;;
        dev2)  j_login dev2 "$JENKINS_DEV2_PASSWORD" ;;
       esac; }
# upload <user> <target> <local-file> <note> -> echoes build number
upload() { as "$1"; j_trigger "$UP" -F "TARGET=$2" -F "COMPOSE_FILE=@$3" -F "CHANGE_NOTE=$4"; }
refresh() { as admin; local n; n=$(j_trigger "$REFRESH"); j_wait "$REFRESH" "$n"; }
choices() {
    curl -g -fsS -u "admin:$JENKINS_ADMIN_PASSWORD" \
      "$JENKINS_HTTP/job/cd/job/upload-compose/api/json?tree=property[parameterDefinitions[name,choices]]" \
      | python3 -c "import json,sys
for p in json.load(sys.stdin)['property']:
  for d in p.get('parameterDefinitions',[]):
    if d['name']=='TARGET': print('\n'.join(d['choices']))"
}
same_as() { diff -q <(GL raw "$1") "$2" >/dev/null; }
cannot_trigger() { ! j_trigger "$1" >/dev/null 2>&1; }

echo "== 0. reset the CD repo to the seed content"
for f in $PAY $ORD $MON; do same_as "$f" "$SEED/$f" || GL put "$f" "$SEED/$f" "test: reset $f"; done
GL rm "$NEW" "test: reset (remove billing)"
check "refresh-paths SUCCESS" [ "$(refresh)" = SUCCESS ]

echo "== 1. access control (dev1)"
as dev1
check "dev1 cannot see cd-admin"               [ "$(j_status /job/cd-admin/)" != 200 ]
check "dev1 cannot open job configuration"     [ "$(j_status /job/cd/job/upload-compose/configure)" = 403 ]
check "dev1 cannot open Manage Jenkins"        [ "$(j_status /manage/)" = 403 ]
check "dev1 cannot browse the job workspace"   [ "$(j_status /job/cd/job/upload-compose/ws/)" != 200 ]
check "dev1 cannot see credentials"            [ "$(j_status /manage/credentials/)" = 403 ]
check "dev1 can open upload-compose"           [ "$(j_status /job/cd/job/upload-compose/)" = 200 ]
check "dev1 cannot trigger refresh-paths"      cannot_trigger "$REFRESH"

echo "== 2. the dropdown lists exactly the compose files in the repo"
expected=$(printf '%s\n' $MON services/notification/docker-compose.yaml $ORD $PAY)
check "TARGET choices = the 4 compose files (no .md, no .env.example)" [ "$(choices)" = "$expected" ]

echo "== 3. show-compose prints the file from git"
as dev1; n=$(j_trigger "$SHOW" -F "TARGET=$PAY"); r=$(j_wait "$SHOW" "$n")
check "show SUCCESS"                           [ "$r" = SUCCESS ]
check "console prints the file"                grep -q 'payment-api:1.4.0' <(j_console "$SHOW" "$n")

echo "== 4. dev1 uploads a new payment compose file"
sed 's/1.4.0/1.5.0/; s/info/debug/' "$SEED/$PAY" > "$TMP/payment.yml"
before=$(GL count)
n=$(upload dev1 "$PAY" "$TMP/payment.yml" "bump payment-api to 1.5.0"); r=$(j_wait "$UP" "$n")
check "upload SUCCESS"                         [ "$r" = SUCCESS ]
[ "$r" = SUCCESS ] || j_console "$UP" "$n" | tail -30
check "file in git is byte-identical to the upload" same_as "$PAY" "$TMP/payment.yml"
last=$(GL last "$PAY")
check "commit author is dev1"                  [ "$(sed -n 2p <<<"$last")" = dev1 ]
check "commit message has the change note"     grep -q 'bump payment-api to 1.5.0' <<<"$last"
check "commit message has Uploaded-by: dev1"   grep -q 'Uploaded-by: dev1' <<<"$last"
check "exactly one new commit"                 [ "$(GL count)" = $((before+1)) ]
check "console links the commit"               grep -q "/-/commit/$(head -1 <<<"$last")" <(j_console "$UP" "$n")
check "other files untouched (orders)"         same_as "$ORD" "$SEED/$ORD"

echo "== 5. show-compose sees the new version"
as dev2; n=$(j_trigger "$SHOW" -F "TARGET=$PAY"); j_wait "$SHOW" "$n" >/dev/null
check "show prints 1.5.0"                      grep -q 'payment-api:1.5.0' <(j_console "$SHOW" "$n")
check "show prints the last change by dev1"    grep -q 'Uploaded-by: dev1' <(j_console "$SHOW" "$n")

echo "== 6. same file again -> nothing to commit"
before=$(GL count)
n=$(upload dev2 "$PAY" "$TMP/payment.yml" "again"); r=$(j_wait "$UP" "$n")
check "identical upload SUCCESS"               [ "$r" = SUCCESS ]
check "...says nothing to commit"              grep -q 'nothing to commit' <(j_console "$UP" "$n")
check "...no new commit"                       [ "$(GL count)" = "$before" ]

echo "== 7. bad uploads change nothing"
before=$(GL count)
: > "$TMP/empty.yml"
n=$(upload dev1 "$ORD" "$TMP/empty.yml" "empty"); r=$(j_wait "$UP" "$n")
check "empty file -> FAILURE"                  [ "$r" = FAILURE ]
as dev1; n=$(j_trigger "$UP" -F "TARGET=$ORD" -F "CHANGE_NOTE=no file"); r=$(j_wait "$UP" "$n")
check "no file -> FAILURE"                     [ "$r" = FAILURE ]
as dev1
if n=$(j_trigger "$UP" -F "TARGET=../../etc/evil.yml" -F "COMPOSE_FILE=@$TMP/payment.yml" 2>/dev/null); then
    r=$(j_wait "$UP" "$n"); check "path not in the list -> FAILURE ($r)" [ "$r" = FAILURE ]
else
    ok "path not in the list -> rejected by Jenkins (not a valid choice)"
fi
check "repo unchanged by all of the above"     [ "$(GL count)" = "$before" ]

echo "== 8. two developers upload at the same time (different files)"
sed 's/2.1.3/2.2.0/' "$SEED/$ORD" > "$TMP/orders.yml"
sed 's/1.5.0/1.5.1/' "$TMP/payment.yml" > "$TMP/payment2.yml"
n1=$(upload dev1 "$PAY" "$TMP/payment2.yml" "payment 1.5.1")
n2=$(upload dev2 "$ORD" "$TMP/orders.yml" "orders 2.2.0")
r1=$(j_wait "$UP" "$n1"); r2=$(j_wait "$UP" "$n2")
check "both uploads SUCCESS ($r1/$r2)"         [ "$r1/$r2" = SUCCESS/SUCCESS ]
check "payment has 1.5.1"                      same_as "$PAY" "$TMP/payment2.yml"
check "orders has 2.2.0"                       same_as "$ORD" "$TMP/orders.yml"

echo "== 9. someone pushes directly to the repo -> upload still lands on top"
GL put "$ORD" "$SEED/$ORD" "teammate: direct change to orders"
sed 's/1.5.1/1.6.0/' "$TMP/payment2.yml" > "$TMP/payment3.yml"
n=$(upload dev1 "$PAY" "$TMP/payment3.yml" "payment 1.6.0"); r=$(j_wait "$UP" "$n")
check "upload SUCCESS"                         [ "$r" = SUCCESS ]
check "payment has 1.6.0"                      same_as "$PAY" "$TMP/payment3.yml"
check "teammate's change kept"                 same_as "$ORD" "$SEED/$ORD"

echo "== 10. folder removed from the repo -> upload refused, refresh drops it"
GL rm "$MON" "teammate: remove monitoring"
n=$(upload dev1 "$MON" "$SEED/$MON" "into a removed path"); r=$(j_wait "$UP" "$n")
check "stale choice -> FAILURE"                [ "$r" = FAILURE ]
check "...with a clear message"                grep -q 'is not an existing compose file' <(j_console "$UP" "$n")
check "...and the file is NOT re-created"      bash -c "! python3 ./gitlab.py exists '$MON'"
check "refresh SUCCESS"                        [ "$(refresh)" = SUCCESS ]
check "monitoring gone from the dropdown"      bash -c "! grep -qx '$MON' <<<\"\$1\"" _ "$(choices)"

echo "== 11. new folder in the repo -> refresh adds it, upload works"
GL put "$NEW" "$SEED/$ORD" "teammate: add billing"
check "refresh SUCCESS"                        [ "$(refresh)" = SUCCESS ]
check "billing appears in the dropdown"        grep -qx "$NEW" <(choices)
sed 's/orders-api:2.1.3/billing-api:0.1.0/' "$SEED/$ORD" > "$TMP/billing.yml"
n=$(upload dev2 "$NEW" "$TMP/billing.yml" "billing first version"); r=$(j_wait "$UP" "$n")
check "upload to the new path SUCCESS"         [ "$r" = SUCCESS ]
check "billing file in git"                    same_as "$NEW" "$TMP/billing.yml"

echo "== 12. restore the seed state"
GL rm "$NEW" "test: cleanup"
for f in $PAY $ORD $MON; do same_as "$f" "$SEED/$f" 2>/dev/null || GL put "$f" "$SEED/$f" "test: restore $f"; done
check "refresh SUCCESS"                        [ "$(refresh)" = SUCCESS ]
check "dropdown back to the 4 seed files"      [ "$(choices)" = "$expected" ]

echo
echo "== $pass passed, $fail failed"
[ "$fail" = 0 ]
