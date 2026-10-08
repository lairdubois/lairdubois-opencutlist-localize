# Deployment (Debian 12, NGINX, systemd)

The app runs as one Puma process (Solid Queue inside Puma) on `127.0.0.1:3007`, behind the
server's existing NGINX, at `https://ocl-i18n.lairdubois.fr`. All state lives in
`/srv/ocl-i18n/app/storage` (SQLite databases + the OCL repo checkout).

## One-time setup (as root)

    apt install -y git curl build-essential pkg-config libssl-dev libyaml-dev zlib1g-dev \
      libffi-dev libreadline-dev libgmp-dev libsqlite3-dev sqlite3 libjemalloc2 rsync

    useradd --system --create-home --home-dir /srv/ocl-i18n --shell /bin/bash ocl-i18n
    mkdir -p /srv/ocl-i18n/app && chown ocl-i18n:ocl-i18n /srv/ocl-i18n/app

    # Ruby 4.0.1 for that user only (rbenv + ruby-build)
    sudo -iu ocl-i18n bash -c '
      git clone --depth 1 https://github.com/rbenv/rbenv.git ~/.rbenv
      git clone --depth 1 https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
      ~/.rbenv/bin/rbenv install 4.0.1
    '

    # Environment : fill in RAILS_MASTER_KEY (config/master.key) and the GitHub App values
    install -m 640 -o root -g ocl-i18n deploy/ocl-i18n.env.example /etc/ocl-i18n.env
    # GitHub App private key
    install -m 640 -o root -g ocl-i18n github-app.pem /srv/ocl-i18n/github-app.pem

    install -m 644 deploy/ocl-i18n.service /etc/systemd/system/ && systemctl daemon-reload
    systemctl enable ocl-i18n

    # NGINX + certificate (DNS : ocl-i18n.lairdubois.fr → the server)
    certbot certonly --nginx -d ocl-i18n.lairdubois.fr
    cp deploy/nginx.conf /etc/nginx/sites-available/ocl-i18n.lairdubois.fr
    ln -s ../sites-available/ocl-i18n.lairdubois.fr /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx

Then from the dev machine : `DEPLOY_HOST=root@<server> deploy/deploy.sh`.

First data load, on the server :

    sudo -u ocl-i18n bash -c 'cd /srv/ocl-i18n/app && set -a && source /etc/ocl-i18n.env && set +a &&
      export PATH=/srv/ocl-i18n/.rbenv/versions/4.0.1/bin:$PATH &&
      git clone --depth 1 https://github.com/lairdubois/lairdubois-opencutlist-sketchup-extension.git /tmp/ocl &&
      bin/rails "i18n:bootstrap[/tmp/ocl/src/ladb_opencutlist/yaml/i18n-src]" &&
      bin/rails "i18n:admin[you@example.org,Your Name]" &&
      bin/rails "i18n:login_link[you@example.org]"'

While e-mails are off (`OCL_MAIL_ENABLED=0`), `i18n:login_link[email]` prints a single-use login
link (30 min).

## GitHub

- App callback URL : `https://ocl-i18n.lairdubois.fr/github/callback`
- OCL repo webhook (`push` events, JSON) : `https://ocl-i18n.lairdubois.fr/github/webhook`,
  secret = `OCL_GITHUB_WEBHOOK_SECRET`

## Operations

- Logs : `journalctl -u ocl-i18n -f`
- Console : same as the first data load, with `bin/rails console`
- Backups : the SQLite files run in WAL mode, copy them with
  `sqlite3 storage/production.sqlite3 ".backup '/backup/ocl-i18n-$(date +%F).sqlite3'"`
  (`production_queue`, `_cache` and `_cable` are disposable). `storage/ocl_repo` is re-cloned
  on demand.
