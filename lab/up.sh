#!/usr/bin/env bash
# Bring up the compose-cd lab: GitLab CE (with a CD repository) + Jenkins.
# Idempotent - safe to rerun (also re-pushes jenkins/ to the lab GitLab, so
# pipeline edits reach Jenkins). Secrets are generated once into .env and
# secrets/ (git-ignored).
set -euo pipefail
cd "$(dirname "$0")"
LAB_DIR=$(pwd)
PROJECT_DIR=$(cd .. && pwd)
if docker compose version >/dev/null 2>&1; then DC=(docker compose); else DC=(docker-compose); fi

GITLAB_HTTP=http://localhost:8929
JENKINS_HTTP=http://localhost:8090

gen() { head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c "$1"; }

# ---------------------------------------------------------------- secrets
mkdir -p secrets
if [ ! -f .env ]; then
    ( umask 077; printf 'GITLAB_ROOT_PASSWORD=Gl%s!\n' "$(gen 20)" > .env )
    echo "created .env (GitLab root password)"
fi
if [ ! -f secrets/jenkins.env ]; then
    ( umask 077
      printf 'JENKINS_ADMIN_PASSWORD=%s\nJENKINS_DEV1_PASSWORD=%s\nJENKINS_DEV2_PASSWORD=%s\n' \
        "$(gen 16)" "$(gen 16)" "$(gen 16)" > secrets/jenkins.env )
    echo "created secrets/jenkins.env (Jenkins user passwords)"
fi
if [ ! -f secrets/gitlab-bot-token ]; then
    ( umask 077; printf 'glpat-cd%s' "$(gen 20)" > secrets/gitlab-bot-token )
fi
# Jenkins runs as uid 1000 inside its container and must read this.
chmod 0600 secrets/gitlab-bot-token
[ "$(id -u)" = 1000 ] || echo "WARNING: you are not uid 1000 - Jenkins may not be able to read secrets/gitlab-bot-token"
BOT_TOKEN=$(cat secrets/gitlab-bot-token)

# ----------------------------------------------------------------- gitlab
echo "==> starting GitLab (first start takes several minutes)"
"${DC[@]}" up -d gitlab
until [ "$(docker inspect -f '{{.State.Health.Status}}' cp-gitlab)" = healthy ]; do sleep 10; printf '.'; done; echo " GitLab healthy"

echo "==> GitLab: bot user, group, projects (idempotent)"
docker exec -i cp-gitlab gitlab-rails runner - <<RUBY
org = Organizations::Organization.default_organization rescue nil
admin = User.find_by_username('root')

bot = User.find_by_username('jenkins-bot')
unless bot
  bot = Users::CreateService.new(admin, {
    username: 'jenkins-bot', name: 'Jenkins Bot', email: 'jenkins-bot@compose-cd.local',
    password: SecureRandom.hex(24), skip_confirmation: true,
    organization_id: org&.id
  }.compact).execute.payload[:user]
  raise "bot user not created" unless bot&.persisted?
end
unless bot.personal_access_tokens.active.where(name: ['compose-cd', 'compose-paas']).exists?
  t = bot.personal_access_tokens.create!(name: 'compose-cd', scopes: [:api, :read_repository, :write_repository], expires_at: 300.days.from_now)
  t.set_token('${BOT_TOKEN}'); t.save!
end

group = Group.find_by_full_path('platform')
unless group
  group = Groups::CreateService.new(admin, { name: 'platform', path: 'platform', visibility_level: 0, organization_id: org&.id }.compact).execute
  group = group.payload[:group] if group.respond_to?(:payload)
  raise "group not created" unless group&.persisted?
end
group.add_member(bot, :maintainer) unless group.member?(bot)

%w[cd compose-cd].each do |name|
  next if Project.find_by_full_path("platform/#{name}")
  p = Projects::CreateService.new(admin, { name: name, path: name, namespace_id: group.id, visibility_level: 0, initialize_with_readme: false }).execute
  raise "project #{name}: #{p.errors.full_messages.join(', ')}" unless p.persisted?
end
puts "gitlab objects ok"
RUBY

# Push a directory's content as the single tree of <repo>'s main branch.
#   push_tree <repo> <src_dir> <message> [only_if_empty]
push_tree() {
    local repo=$1 src=$2 msg=$3 only_if_empty=${4:-}
    local url="http://jenkins-bot:${BOT_TOKEN}@localhost:8929/platform/${repo}.git"
    local tmp; tmp=$(mktemp -d)
    if git clone -q "$url" "$tmp/r" 2>/dev/null && [ -n "$(git -C "$tmp/r" rev-parse -q --verify HEAD 2>/dev/null)" ]; then
        if [ -n "$only_if_empty" ]; then rm -rf "$tmp"; echo "   $repo: already seeded, left as is"; return; fi
    else
        rm -rf "$tmp/r"; git init -q -b main "$tmp/r"; git -C "$tmp/r" remote add origin "$url"
    fi
    find "$tmp/r" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    cp -a "$src"/. "$tmp/r"/
    git -C "$tmp/r" add -A
    if git -C "$tmp/r" -c user.name="lab seed" -c user.email=seed@compose-cd.local commit -q -m "$msg" 2>/dev/null; then
        git -C "$tmp/r" push -q origin HEAD:main
        echo "   $repo: pushed"
    else
        echo "   $repo: unchanged"
    fi
    rm -rf "$tmp"
}

echo "==> seeding repositories"
PIPE_SRC=$(mktemp -d)
cp -a "$PROJECT_DIR/jenkins" "$PIPE_SRC"/
push_tree compose-cd "$PIPE_SRC" "lab: sync pipelines from working tree"
rm -rf "$PIPE_SRC"
push_tree cd "$LAB_DIR/seed/cd" "Initial CD repository" only_if_empty

# ---------------------------------------------------------------- jenkins
echo "==> starting Jenkins"
"${DC[@]}" up -d --build jenkins
until curl -fsS -o /dev/null "$JENKINS_HTTP/login" 2>/dev/null; do sleep 5; printf '.'; done; echo " Jenkins up"

set -a; . secrets/jenkins.env; set +a
# Jobs created by JCasC while Jenkins is still loading can be missing until
# the next start (seen in the git-policy lab) - restart once if so.
sleep 5
if ! curl -fsS -u "admin:$JENKINS_ADMIN_PASSWORD" "$JENKINS_HTTP/job/cd-admin/job/refresh-paths/api/json" >/dev/null 2>&1; then
    docker restart cp-jenkins >/dev/null
    until curl -fsS -o /dev/null "$JENKINS_HTTP/login" 2>/dev/null; do sleep 5; printf '.'; done
    echo " Jenkins restarted (jobs registered)"
fi

echo "==> running cd-admin/refresh-paths (generates the developer jobs)"
"$LAB_DIR/jenkins-run.sh" admin "$JENKINS_ADMIN_PASSWORD" cd-admin/refresh-paths >/dev/null
echo "   refresh-paths: SUCCESS"

cat <<MSG

Lab is up.
  Jenkins  $JENKINS_HTTP
     admin  / $JENKINS_ADMIN_PASSWORD      (everything)
     dev1   / $JENKINS_DEV1_PASSWORD      (cd jobs only)
     dev2   / $JENKINS_DEV2_PASSWORD      (cd jobs only)
  GitLab   $GITLAB_HTTP     root / $(grep '^GITLAB_ROOT_PASSWORD=' .env | cut -d= -f2-)
     CD repository: $GITLAB_HTTP/platform/cd
MSG
