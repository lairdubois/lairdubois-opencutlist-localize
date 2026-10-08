# OCL i18n

Translation platform for OpenCutList. A string (`Unit`) has a stable id ; its key is a mutable
attribute, so renaming or moving keys keeps translations, statuses, history and comments.

## Setup

    bin/rails db:setup
    bin/rails "i18n:bootstrap[path/to/ocl/src/ladb_opencutlist/yaml/i18n-src]"
    bin/rails "i18n:admin[you@example.org,Your Name]"
    bin/dev   # or bin/rails server

Production (Debian 12, NGINX, systemd) : see `deploy/README.md`.

## Configuration (environment)

| Variable | Purpose |
|---|---|
| `OCL_GITHUB_REPO` | `owner/name` of the OCL repo (default `lairdubois/lairdubois-opencutlist-sketchup-extension`) |
| `OCL_REPO_URL` | Clone URL, defaults to the GitHub one ; a local path works for tests |
| `OCL_BASE_BRANCH` | Branch fr.yml is read from and PRs target (default `master`) |
| `OCL_I18N_BRANCH` | Branch the translations are pushed to (default `i18n/updates`) |
| `OCL_GITHUB_APP_ID` | ID of the GitHub App that publishes (pushes, PRs and commits show as `<app>[bot]`) |
| `OCL_GITHUB_APP_PRIVATE_KEY` | The App's private key : the PEM itself (`\n` accepted) or a path to the `.pem` file |
| `OCL_GITHUB_APP_CLIENT_ID`, `OCL_GITHUB_APP_CLIENT_SECRET` | The App's OAuth credentials : admins connect their own GitHub account and publish as themselves |
| `OCL_GITHUB_TOKEN` | Fallback without App : token with contents + pull requests write access |
| `OCL_GITHUB_API_URL` | Default `https://api.github.com` ; a fake server for tests |
| `OCL_GITHUB_WEB_URL` | Default `https://github.com` (OAuth endpoints) ; a fake server for tests |
| `OCL_GITHUB_WEBHOOK_SECRET` | Secret of the GitHub `push` webhook pointing to `/github/webhook` |
| `OCL_HOST` | Production host name (default `ocl-i18n.lairdubois.fr`) : allowed host and mail links |
| `OCL_MAIL_FROM`, `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` | Production mail sender and SMTP server |
| `OCL_MAIL_ENABLED` | `1` to actually send e-mails (login links, invitations, comment notifications) ; off by default |
| `ANTHROPIC_API_KEY` | Enables Claude pre-translation suggestions |
| `OCL_I18N_EXPORT_DIR` | Optional : local directory for the plain YAML export |
| `TRANSIFEX_TOKEN`, `TRANSIFEX_RESOURCE` | Migration only : API token and resource slug of the fr.yml resource |
| `TRANSIFEX_ORGANIZATION`, `TRANSIFEX_PROJECT` | Default `opencutlist` / `opencutlist` |
| `TRANSIFEX_LANGUAGE_MAP` | OCL code = Transifex code when they differ, e.g. `zh=zh_CN,pt=pt_PT` |

## Sync model

`Baseline` stores the repo's fr.yml as last reconciled, each key tied to its unit. Syncing diffs the
repo against it (three-way), so changes made in the tool and not yet merged are never read back as
repo changes. Publishing refuses while the repo has unsynced fr.yml changes.

## Publishing

Publishing pushes to a remote repo only with the tool's own credentials (the admin's connected
GitHub account, else the GitHub App, else `OCL_GITHUB_TOKEN`) : git credential helpers and prompts are disabled, and without credentials the
publish button is off. A local `OCL_REPO_URL` (path or `file://`) needs none.

GitHub App : Settings → Developer settings → GitHub Apps → New, webhook inactive, repository
permissions Contents and Pull requests read & write, "Only on this account" ; generate a private
key, install the App on the OCL repo only. Installation tokens (1 h) are requested per repo and
cached in memory.

Admin accounts : with the App's client id and a client secret (App settings → "Generate a new client
secret"), each admin can click "Connecter GitHub" on the publication page. Set the App's callback URL
to `https://<host>/github/callback` and keep "Expire user authorization tokens" on. The admin's user
access token (8 h, refreshed with a 6 months refresh token, stored encrypted) then pushes and opens
the PR in their name ; it only reaches the repos the App is installed on, and only with the App's
permissions. The account is refused unless it has write access to the OCL repo. Without a connected
account, publishing falls back to the App. Disconnecting revokes the authorization on GitHub.
Encryption keys are derived from `secret_key_base` : changing it means admins reconnect.
