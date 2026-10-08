#!/usr/bin/env bash
# Ships the working tree to the server, then installs gems, builds assets, migrates and restarts.
# Usage : DEPLOY_HOST=root@lairdubois.fr deploy/deploy.sh
set -euo pipefail

host="${DEPLOY_HOST:?DEPLOY_HOST=user@server}"
app=/var/www/ocl-i18n/app
cd "$(dirname "$0")/.."

rsync -az --delete \
  --exclude /.git/ --exclude /.idea/ --exclude /.env\* --exclude /config/\*.key \
  --exclude /storage/ --exclude /log/ --exclude /tmp/ \
  --exclude /public/assets/ --exclude /app/assets/builds/ --exclude /vendor/bundle/ --exclude /.bundle/ \
  ./ "$host:$app/"

ssh "$host" bash -s <<EOF
set -euo pipefail
chown -R ocl-i18n:ocl-i18n $app
cd $app
sudo -u ocl-i18n bash -c '
  set -euo pipefail
  set -a; source /etc/ocl-i18n.env; set +a
  export PATH=/var/www/ocl-i18n/.rbenv/versions/4.0.1/bin:\$PATH
  mkdir -p storage log tmp
  chmod 750 storage
  bundle config set --local deployment true
  bundle config set --local without "development test"
  bundle install --quiet
  bin/rails assets:precompile
  bin/rails db:prepare
'
systemctl restart ocl-i18n
sleep 3
curl -fsS -o /dev/null -w "up : %{http_code}\n" http://127.0.0.1:3007/up
EOF
