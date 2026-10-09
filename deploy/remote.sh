#!/usr/bin/env bash
# Server side of deploy/deploy.sh, run as root : sudo bash remote.sh <uploaded tree>
set -euo pipefail

src="${1:?uploaded tree}"
home=/var/www/localize.opencutlist.org
app=$home/app
[ -f /etc/ocl-localize.env ] || { echo "server not set up : deploy/deploy.sh setup" >&2; exit 1; }
[ -x "$home/.rbenv/versions/4.0.1/bin/bundle" ] || { echo "Ruby 4.0.1 missing : deploy/deploy.sh setup" >&2; exit 1; }

# What only exists on the server (data, builds, gems) is excluded, hence kept by --delete
rsync -a --delete --chown=ocl-localize:ocl-localize \
  --exclude /storage/ --exclude /log/ --exclude /tmp/ \
  --exclude /public/assets/ --exclude /app/assets/builds/ --exclude /vendor/bundle/ --exclude /.bundle/ \
  "$src/" "$app/"

cd "$app"
sudo -u ocl-localize bash -c "
  set -euo pipefail
  set -a; source /etc/ocl-localize.env; set +a
  export PATH=$home/.rbenv/versions/4.0.1/bin:\$PATH
  mkdir -p storage log tmp
  chmod 750 storage
  # Propshaft only adds the app/assets/* directories that exist at boot : the Tailwind build goes here
  mkdir -p app/assets/builds
  bundle config set --local deployment true
  bundle config set --local without development:test
  bundle install --quiet
  bin/rails assets:precompile
  bin/rails db:prepare
"

systemctl restart ocl-localize
for _ in $(seq 1 20); do
  curl -fsS -o /dev/null http://127.0.0.1:3007/up 2>/dev/null && { echo "up"; exit 0; }
  sleep 1
done
echo "not answering on /up : journalctl -u ocl-localize -n 50" >&2
exit 1
