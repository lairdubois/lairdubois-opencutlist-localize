# Deployment (Debian 12, NGINX, systemd)

The app runs as one Puma process (Solid Queue inside Puma) on `127.0.0.1:3007`, behind the
server's existing NGINX, at `https://localize.opencutlist.org`. It works on the real OCL repo :
publishing pushes the i18n branch to GitHub and opens a pull request there. No e-mail is sent
(`OCL_MAIL_ENABLED=0`).

    /var/www/localize.opencutlist.org/   home of the ocl-localize system user
      .rbenv/                            Ruby 4.0.1
      app/                               the code (deploy/deploy.sh), NGINX serves app/public
      app/storage/                       SQLite databases + the OCL repo checkout : the only state
      acme/                              Let's Encrypt challenges (certbot webroot)
      github-app.pem                     the GitHub App's private key
    /etc/ocl-localize.env                environment (secrets)

## Prerequisites

- DNS : `localize.opencutlist.org` → the server (the certificate is requested during the setup).
- An SSH account with sudo on the server, and `rsync` there (`sudo apt install rsync` if missing).
- certbot (webroot mode : its NGINX plugin is not needed).
- The GitHub App (see "Publishing" in the main `README.md`) : repository permissions Contents and
  Pull requests read & write, installed on the OCL repo only, callback URL
  `https://localize.opencutlist.org/github/callback`, a private key and a client secret generated.
- Admin access to the OCL repo (webhook).

## First install

1. From the dev machine :

       DEPLOY_HOST=you@<server> deploy/deploy.sh setup

   It uploads the code to `~/ocl-localize-deploy` on the server (no secrets : `.env*` and `config/*.key`
   are excluded), then, with sudo (one password prompt), runs `deploy/setup.sh` and `deploy/remote.sh`.
   The OCL base branch (synced with, published from, pull requests' base) defaults to `master` ;
   another one is passed as `OCL_BASE_BRANCH` :

       DEPLOY_HOST=you@<server> OCL_BASE_BRANCH=8.0.0 deploy/deploy.sh setup

   `deploy/setup.sh` (safe to run again, keeps what already exists) :
   - apt packages : runtime ones (git, sqlite3, jemalloc, rsync, openssl) and build ones for Ruby
     and native gems (build-essential, pkg-config, libssl / libyaml / zlib / libffi `-dev`)
   - the `ocl-localize` system user, home `/var/www/localize.opencutlist.org`
   - Ruby 4.0.1 through rbenv (compiles for a few minutes the first time)
   - `/etc/ocl-localize.env` from `ocl-localize.env.example`, with a generated `SECRET_KEY_BASE` and
     `OCL_BASE_BRANCH` (an existing file is kept : the setup only warns if its branch differs)
   - the systemd service, the `ocl-localize-rails` wrapper in `/usr/local/bin`
   - the certificate (certbot webroot, first time only : an HTTP-only site serves the challenge
     from `acme/`) and the NGINX site, then `nginx -t` and reload

   `deploy/remote.sh` : copy into `app/`, gems, assets, migrations, restart, `/up` check.
   The app then runs with publishing off (no GitHub credentials yet).

2. GitHub credentials, on the server :
   - the App's private key in `/var/www/localize.opencutlist.org/github-app.pem`
     (`sudo install -m 640 -o root -g ocl-localize <key>.pem /var/www/localize.opencutlist.org/github-app.pem`) ;
   - in `/etc/ocl-localize.env` : `OCL_GITHUB_APP_ID`, `OCL_GITHUB_APP_CLIENT_ID`,
     `OCL_GITHUB_APP_CLIENT_SECRET`, and `OCL_GITHUB_WEBHOOK_SECRET` = `openssl rand -hex 32` ;
     `TRANSIFEX_TOKEN` for the migration, `ANTHROPIC_API_KEY` if wanted ;
   - `sudo systemctl restart ocl-localize`.

3. Push webhook, on GitHub (OCL repo admin) : Settings → Webhooks → Add webhook,
   payload URL `https://localize.opencutlist.org/github/webhook`, content type **`application/json`**
   (the form-encoded default is not parsed), secret = `OCL_GITHUB_WEBHOOK_SECRET`, "Just the push event".
   - Check the `ping` in the webhook's "Recent Deliveries" : 200 = OK, 401 = secrets differ,
     404 = secret not loaded on the server.
   - What it does : after each push to the base branch, a job (`RepoFrCheckJob`, run by Solid Queue in
     Puma, `SOLID_QUEUE_IN_PUMA=1`) reads the pushed fr.yml through the GitHub API and shows admins a
     "sync" banner when it has changes to sync, or clears it when it has none (merging the tool's own
     pull request, for instance). A fr.yml missing from the push (deleted or moved) shows the banner too,
     and the sync page then says it is not found. It only warns : nothing is synced automatically.

4. First data load, from the base branch on GitHub (replace `master` if needed), and your admin account :

       cd /tmp && sudo -u ocl-localize git clone -q --depth 1 --branch master https://github.com/lairdubois/lairdubois-opencutlist-sketchup-extension.git /tmp/ocl
       sudo ocl-localize-rails "i18n:bootstrap[/tmp/ocl/src/ladb_opencutlist/yaml/i18n-src]"
       sudo rm -rf /tmp/ocl
       sudo ocl-localize-rails "i18n:admin[you@example.org,Your Name]"
       sudo ocl-localize-rails "i18n:login_link[you@example.org]"

   Logging in : e-mails are off, so `i18n:login_link[email]` prints a single-use link (30 min) to
   hand over. Other accounts are created from the users page.

5. In the tool : "Connecter GitHub" on the publication page (optional : without it, publishing uses
   the App), then the Transifex import from the migration page (`/migration`).

## Updates

    DEPLOY_HOST=you@<server> deploy/deploy.sh

(`setup` again is harmless : it keeps the user, Ruby, environment and certificate.)

## Running commands on the server

    sudo ocl-localize-rails console     # or any bin/rails task, as ocl-localize with the production environment

## Removing the ocl-i18n install

The former sandbox install ran as user `ocl-i18n` in `/var/www/ocl-i18n.lairdubois.fr`, at
`https://ocl-i18n.lairdubois.fr`. Its data is not carried over (sandbox only). Stop it before the
first install (it holds port 3007) : `sudo systemctl disable --now ocl-i18n`, then, once the new
install is checked (in a root shell) :

    rm /etc/nginx/sites-enabled/ocl-i18n.lairdubois.fr /etc/nginx/sites-available/ocl-i18n.lairdubois.fr
    nginx -t && systemctl reload nginx
    certbot delete --cert-name ocl-i18n.lairdubois.fr
    rm /etc/systemd/system/ocl-i18n.service /usr/local/bin/ocl-i18n-rails /etc/ocl-i18n.env
    systemctl daemon-reload
    userdel -r ocl-i18n   # deletes /var/www/ocl-i18n.lairdubois.fr
    rm -rf ~<deploy account>/ocl-i18n-deploy

## Logs and backups

- Logs : `journalctl -u ocl-localize -f`
- Backups (as root, from `/var/www/localize.opencutlist.org`) : the SQLite files run in WAL mode, copy them with
  `sqlite3 app/storage/production.sqlite3 ".backup '/backup/ocl-localize-$(date +%F).sqlite3'"`
  (`production_queue`, `_cache` and `_cable` are disposable). `storage/ocl_repo` is re-cloned
  on demand.
