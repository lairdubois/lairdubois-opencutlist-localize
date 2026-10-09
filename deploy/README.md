# Deployment (Debian 12, NGINX, systemd)

The app runs as one Puma process (Solid Queue inside Puma) on `127.0.0.1:3007`, behind the
server's existing NGINX, at `https://ocl-i18n.lairdubois.fr`.

    /var/www/ocl-i18n.lairdubois.fr/   home of the ocl-i18n system user
      .rbenv/                          Ruby 4.0.1
      app/                             the code (deploy/deploy.sh), NGINX serves app/public
      app/storage/                     SQLite databases + the OCL repo checkout : the only state
      sandbox-repo.git                 sandbox only : the local repo publishing pushes to
      acme/                            Let's Encrypt challenges (certbot webroot)
    /etc/ocl-i18n.env                  environment (secrets)

It first runs as a **sandbox** : publishing commits and pushes to `sandbox-repo.git` on the
server, never to GitHub (no GitHub credentials are configured, so no pull request either), and
no e-mail is sent. Going to production = reset the data and switch the environment
(see the end).

## Prerequisites

- DNS : `ocl-i18n.lairdubois.fr` → the server (the certificate is requested during the setup).
- An SSH account with sudo on the server, and `rsync` there (`sudo apt install rsync` if missing).
- certbot (webroot mode : its NGINX plugin is not needed).

## First install

From the dev machine :

    DEPLOY_HOST=you@<server> deploy/deploy.sh setup

It uploads the code to `~/ocl-i18n-deploy` on the server (no secrets : `.env*` and `config/*.key`
are excluded), then, with sudo (one password prompt), runs `deploy/setup.sh` and `deploy/remote.sh`.

`deploy/setup.sh` (safe to run again, keeps what already exists) :
- apt packages : runtime ones (git, sqlite3, jemalloc, rsync, openssl) and build ones for Ruby
  and native gems (build-essential, pkg-config, libssl / libyaml / zlib / libffi `-dev`)
- the `ocl-i18n` system user, home `/var/www/ocl-i18n.lairdubois.fr`
- Ruby 4.0.1 through rbenv (compiles for a few minutes the first time)
- `sandbox-repo.git` : bare clone of the OCL repo's master
- `/etc/ocl-i18n.env` from `ocl-i18n.env.example`, with a generated `SECRET_KEY_BASE`
- the systemd service, the `ocl-i18n-rails` wrapper in `/usr/local/bin`
- the certificate (certbot webroot, first time only : an HTTP-only site serves the challenge
  from `acme/`) and the NGINX site, then `nginx -t` and reload

`deploy/remote.sh` : copy into `app/`, gems, assets, migrations, restart, `/up` check.

Then on the server, first data load (from the sandbox repo's fr.yml) and your admin account :

    cd /tmp && sudo -u ocl-i18n git clone -q /var/www/ocl-i18n.lairdubois.fr/sandbox-repo.git /tmp/ocl
    sudo ocl-i18n-rails "i18n:bootstrap[/tmp/ocl/src/ladb_opencutlist/yaml/i18n-src]"
    sudo rm -rf /tmp/ocl
    sudo ocl-i18n-rails "i18n:admin[you@example.org,Your Name]"
    sudo ocl-i18n-rails "i18n:login_link[you@example.org]"

Logging in : e-mails are off, so `i18n:login_link[email]` prints a single-use link (30 min) to
hand over. Testers' accounts are created from the users page.

## Updates

    DEPLOY_HOST=you@<server> deploy/deploy.sh

## Running commands on the server

    sudo ocl-i18n-rails console     # or any bin/rails task, as ocl-i18n with the production environment

## Sandbox operations

- Simulate a change on the OCL side (then "Synchroniser" in the tool) : pull GitHub's latest
  master into the sandbox repo, as ocl-i18n (`sudo -iu ocl-i18n`)
  `git -C ~/sandbox-repo.git fetch -q --depth 1 https://github.com/lairdubois/lairdubois-opencutlist-sketchup-extension.git +master:master`
- See what "Publier" produced (as ocl-i18n too) : `git -C ~/sandbox-repo.git log --stat i18n/updates`
- Reset everything (in a root shell, from `/var/www/ocl-i18n.lairdubois.fr`) :
  `systemctl stop ocl-i18n`, delete `app/storage/production*.sqlite3*`, `app/storage/ocl_repo`
  and `sandbox-repo.git`, then `deploy/deploy.sh setup` (re-clones the sandbox repo, recreates
  the databases) and the first data load again.

## Going to production

1. Stop the service, delete the databases (all four, with their `-wal` / `-shm` files),
   `app/storage/ocl_repo` and `sandbox-repo.git` (in a root shell, from `/var/www/ocl-i18n.lairdubois.fr`) :

       systemctl stop ocl-i18n
       rm -f app/storage/production*.sqlite3*
       rm -rf app/storage/ocl_repo sandbox-repo.git
2. In `/etc/ocl-i18n.env` : remove `OCL_REPO_URL`, fill in the `OCL_GITHUB_*` variables, put the
   App's private key in `/var/www/ocl-i18n.lairdubois.fr/github-app.pem` (`root:ocl-i18n`, mode 640).
3. GitHub App callback URL : `https://ocl-i18n.lairdubois.fr/github/callback` ; OCL repo webhook
   (`push` events, JSON) : `https://ocl-i18n.lairdubois.fr/github/webhook`, secret =
   `OCL_GITHUB_WEBHOOK_SECRET`.
   - Generate the secret with `openssl rand -hex 32`, put it in `/etc/ocl-i18n.env`, restart the service.
   - On GitHub (repo admin) : Settings → Webhooks → Add webhook, content type **`application/json`**
     (the form-encoded default is not parsed), "Just the push event", same secret.
   - Check the `ping` in the webhook's "Recent Deliveries" : 200 = OK, 401 = secrets differ,
     404 = secret not loaded on the server.
   - What it does : after each push to the base branch, a job (`RepoFrCheckJob`, run by Solid Queue in
     Puma, `SOLID_QUEUE_IN_PUMA=1`) reads the pushed fr.yml through the GitHub API and shows admins a
     "sync" banner when it has changes to sync, or clears it when it has none (merging the tool's own
     pull request, for instance). A fr.yml missing from the push (deleted or moved) shows the banner too,
     and the sync page then says it is not found. It only warns : nothing is synced automatically.
4. `deploy/deploy.sh` (recreates the databases, restarts ; not `setup` : it would re-clone the
   sandbox repo), first data load from a clone of the real repo, Transifex import.

## Logs and backups

- Logs : `journalctl -u ocl-i18n -f`
- Backups (as root, from `/var/www/ocl-i18n.lairdubois.fr`) : the SQLite files run in WAL mode, copy them with
  `sqlite3 app/storage/production.sqlite3 ".backup '/backup/ocl-i18n-$(date +%F).sqlite3'"`
  (`production_queue`, `_cache` and `_cable` are disposable). `storage/ocl_repo` is re-cloned
  on demand.
