#!/usr/bin/env bash
# Ships the working tree to the server, then installs gems, builds assets, migrates and restarts.
# Usage : DEPLOY_HOST=you@lairdubois.fr deploy/deploy.sh [setup]
# The account only needs sudo : the code goes to ~/ocl-i18n-deploy first, then deploy/remote.sh
# (one sudo password prompt) copies it into the app and restarts the service.
# "setup" runs deploy/setup.sh before (packages, user, Ruby, service, NGINX : first time only).
set -euo pipefail

host="${DEPLOY_HOST:?DEPLOY_HOST=user@server}"
cd "$(dirname "$0")/.."

rsync -az --delete \
  --exclude /.git/ --exclude /.idea/ --exclude /.env\* --exclude /config/\*.key \
  --exclude /storage/ --exclude /log/ --exclude /tmp/ \
  --exclude /public/assets/ --exclude /app/assets/builds/ --exclude /vendor/bundle/ --exclude /.bundle/ \
  ./ "$host:ocl-i18n-deploy/"

remote='sudo bash "$HOME/ocl-i18n-deploy/deploy/remote.sh" "$HOME/ocl-i18n-deploy"'
[ "${1:-}" = setup ] && remote="sudo bash \"\$HOME/ocl-i18n-deploy/deploy/setup.sh\" && $remote"
ssh -t "$host" "$remote"
