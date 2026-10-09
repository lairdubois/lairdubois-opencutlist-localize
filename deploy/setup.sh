#!/usr/bin/env bash
# One-time server setup, run as root by `deploy/deploy.sh setup` ; safe to run again
# (existing user, Ruby, environment file and certificate are kept).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
domain=localize.opencutlist.org
home=/var/www/$domain
ruby=4.0.1
# OCL branch the app syncs with and publishes from : first argument (deploy.sh's OCL_BASE_BRANCH)
branch="${1:-master}"
[[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "Invalid branch: $branch" >&2; exit 1; }

step() { printf '\n== %s\n' "$*"; }

step "Packages"
apt-get update -q
# Runtime : git (the app shells out to it), sqlite3 (backups), jemalloc, rsync (deploy), openssl (secret)
apt-get install -y -q git curl rsync sqlite3 libjemalloc2 openssl
# Build only (Ruby via ruby-build, native gem extensions) ; sqlite3 and nokogiri gems are precompiled
apt-get install -y -q build-essential pkg-config libssl-dev libyaml-dev zlib1g-dev libffi-dev

step "User ocl-localize ($home)"
id ocl-localize >/dev/null 2>&1 || useradd --system --create-home --home-dir "$home" --shell /bin/bash ocl-localize
chmod 755 "$home" # NGINX (www-data) reads app/public
install -d -o ocl-localize -g ocl-localize "$home/app"
cd "$home"

step "Ruby $ruby (rbenv, compiles for a few minutes the first time)"
# Explicit paths : sudo -i would escape a "~" in the command, leaving it unexpanded
rbenv_root=$home/.rbenv
sudo -u ocl-localize env HOME="$home" RBENV_ROOT="$rbenv_root" bash -c "
  set -euo pipefail
  [ -d $rbenv_root ] || git clone -q --depth 1 https://github.com/rbenv/rbenv.git $rbenv_root
  [ -d $rbenv_root/plugins/ruby-build ] || git clone -q --depth 1 https://github.com/rbenv/ruby-build.git $rbenv_root/plugins/ruby-build
  git -C $rbenv_root/plugins/ruby-build pull -q
  $rbenv_root/bin/rbenv install --skip-existing $ruby
"
[ -x "$rbenv_root/versions/$ruby/bin/bundle" ] || { echo "Ruby $ruby missing in $rbenv_root/versions" >&2; exit 1; }

step "Environment /etc/ocl-localize.env"
if [ -f /etc/ocl-localize.env ]; then
  current=$(sed -n 's/^OCL_BASE_BRANCH=//p' /etc/ocl-localize.env | tail -n 1)
  [ "${current:-master}" = "$branch" ] && echo "kept" ||
    echo "kept, with OCL_BASE_BRANCH=${current:-master} (not $branch) : edit it there if needed"
else
  install -m 640 -o root -g ocl-localize /dev/null /etc/ocl-localize.env
  sed -e "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$(openssl rand -hex 64)|" \
    -e "s|^OCL_BASE_BRANCH=.*|OCL_BASE_BRANCH=$branch|" "$here/ocl-localize.env.example" > /etc/ocl-localize.env
  echo "created, with a generated SECRET_KEY_BASE and OCL_BASE_BRANCH=$branch"
fi

step "systemd service"
install -m 644 "$here/ocl-localize.service" /etc/systemd/system/ocl-localize.service
systemctl daemon-reload
systemctl enable -q ocl-localize

step "Rails command wrapper (sudo ocl-localize-rails console)"
install -m 755 "$here/ocl-localize-rails" /usr/local/bin/ocl-localize-rails

step "Certificate $domain"
# Webroot : works without certbot's NGINX plugin ; renewals use the same challenge location
install -d -m 755 "$home/acme"
if [ -d "/etc/letsencrypt/live/$domain" ]; then
  echo "kept"
else
  # HTTP-only site first : the full one refers to the certificate files
  cat > "/etc/nginx/sites-available/$domain" <<NGINX
server {
  listen 80;
  listen [::]:80;
  server_name $domain;
  location /.well-known/acme-challenge/ { root $home/acme; }
}
NGINX
  ln -sf "../sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
  nginx -t
  systemctl reload nginx
  certbot certonly --webroot -w "$home/acme" -d "$domain" --deploy-hook "systemctl reload nginx"
fi

step "NGINX site"
install -m 644 "$here/nginx.conf" "/etc/nginx/sites-available/$domain"
ln -sf "../sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
nginx -t
systemctl reload nginx
