#!/usr/bin/env bash
# Ships the working tree to the server, then installs gems, builds assets, migrates and restarts.
# Usage : DEPLOY_HOST=you@lairdubois.fr [OCL_BASE_BRANCH=master] deploy/deploy.sh [setup]
# The account only needs sudo : the code goes to ~/ocl-localize-deploy first, then deploy/remote.sh
# (one sudo password prompt) copies it into the app and restarts the service.
# "setup" runs deploy/setup.sh before (packages, user, Ruby, service, NGINX : first time only) ;
# OCL_BASE_BRANCH (default master) is the OCL branch it writes into a new /etc/ocl-localize.env.
set -euo pipefail

host="${DEPLOY_HOST:?DEPLOY_HOST=user@server}"
branch="${OCL_BASE_BRANCH:-master}"
git check-ref-format --branch "$branch" >/dev/null 2>&1 && [[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] ||
  { echo "Invalid OCL_BASE_BRANCH: $branch" >&2; exit 1; }
cd "$(dirname "$0")/.."

rsync -az --delete \
  --exclude /.git/ --exclude /.idea/ --exclude /.env\* --exclude /config/\*.key \
  --exclude /storage/ --exclude /log/ --exclude /tmp/ \
  --exclude /public/assets/ --exclude /app/assets/builds/ --exclude /vendor/bundle/ --exclude /.bundle/ \
  ./ "$host:ocl-localize-deploy/"

remote='sudo bash "$HOME/ocl-localize-deploy/deploy/remote.sh" "$HOME/ocl-localize-deploy"'
[ "${1:-}" = setup ] && remote="sudo bash \"\$HOME/ocl-localize-deploy/deploy/setup.sh\" $branch && $remote"
ssh -t "$host" "$remote"
