# CLAUDE.md

Guidance for Claude Code in this repository. Setup, configuration and the sync model are in `README.md`.

## What This Is

In-house translation platform replacing Transifex for **OpenCutList** (SketchUp extension, repo
`~/DevProjects/lairdubois-opencutlist-sketchup-extension`, i18n sources in
`src/ladb_opencutlist/yaml/i18n-src/*.yml`, `fr.yml` = source language, `en.yml` = fallback).

Goal : reshape the fr source (rename / move keys, edit texts) without invalidating translators' work.
Weblate was evaluated and rejected.

## Environment

- Rails 8.1 + SQLite (WAL), Tailwind (tailwindcss-rails), Turbo + importmap, Ruby 4.0 from Homebrew :
  prefix commands with `PATH=/opt/homebrew/opt/ruby/bin:$PATH`.
- Dev server on port **3007** : `set -a; source .env; set +a; bin/rails server -p 3007`.
  `bin/rails server` alone does not rebuild Tailwind : new classes need `bin/dev` or
  `bin/rails tailwindcss:watch` (or `:build`). `app/assets/builds/` is generated.
- `.env` (git-ignored) holds `TRANSIFEX_TOKEN` (secret : never print it, read it via `source .env`
  without echoing) and `TRANSIFEX_RESOURCE=v6`.
- Without `OCL_REPO_URL` the app points to the real GitHub repo : don't click / call "Publier"
  while testing unless a local repo is configured.
- Not deployed yet : target is the user's Debian 12 server next to L'Air du Bois, behind its NGINX,
  at `ocl-i18n.lairdubois.fr`, systemd + rbenv, no Docker (`deploy/`).

## Hard rules

- **No e-mail to translators** for now : `perform_deliveries` stays off unless `OCL_MAIL_ENABLED=1`.
  Never enable it without asking. Dev shows the login link on the login page.
- Don't apply the Transifex import, publish, push or deploy without an explicit request.

## Core design

- `Unit` id is stable, `key` is a mutable attribute : translations, revisions, comments and
  suggestions follow renames. Archive instead of delete (`archived_at`, partial unique index on key).
- Outdated = `Translation.source_hash != Unit.source_hash`. A minor fr edit moves the translations'
  hash along, a major one leaves them outdated (`UnitOperations#edit_source`).
- `Revision` is the append-only history. All admin mutations go through `UnitOperations` /
  `TranslationOperations`.
- i18next nesting `$t(key)` (~197 in fr) is rewritten on leaf and branch renames
  (`UnitOperations#rewrite_references`).
- `Baseline` = repo fr.yml as last reconciled, keyed to unit ids. `SourceSync` diffs repo vs
  baseline (three-way) ; `Baseline.record!` keeps the previous unit id per repo key (archived
  units included) so pending tool renames / deletions survive a sync.
- Rename detection : same fr text, disambiguated by key similarity (trailing segments ×100 +
  leading) ; ambiguous pairs are skipped.
- `Publisher` refuses while the repo fr.yml has unsynced changes ; rewrites quoted key literals in
  js / twig / ruby and warns on leftover dynamic uses. `OclRepo` = shallow checkout in
  `storage/ocl_repo`, force-pushed i18n branch. `GithubAuth` : the publishing admin's GitHub App user
  access token when connected (`GithubOauth`, encrypted on `User`, refreshed under a row lock), else
  App installation tokens (commits / PRs as `<app>[bot]`), else `OCL_GITHUB_TOKEN` ; passed via
  `http.extraHeader` only, git credential helpers and prompts disabled, no push to a remote without
  credentials.
- `Pretranslator` (anthropic gem, `claude-opus-5-5`, structured output) only creates `Suggestion`s,
  never translations.
- Migration : `TransifexImport` (API v3, parallel fetch, keys mapped through the Baseline ;
  ours kept when edited in the tool = conflict), `TransifexRoster` (API exposes no e-mails).

## YAML I/O

- Read through Psych nodes (raw scalars) : `no: No` must stay "No". gulp uses js-yaml (YAML 1.2),
  so unquoted Yes/No in OCL files are not a bug.
- Writer : plain scalar if `Psych.safe_load` round-trips, else literal block `|`/`|-`/`|+`,
  else double quotes with custom escaping (not `to_json`, which escapes `<`).
- Transifex exports untranslated strings as `""` ; gulp falls back to en for `""` and missing
  keys alike, so import skips `""`.

## Gotchas

- Turbo ignores a 200 HTML answer to a form POST : forms that render a page need
  `data: { turbo: false }`.
- Turbo hover prefetch fires GETs : single-use tokens are consumed by POST (login confirm page).
- `Unit` default_scope `order(:position)` leaks through `merge` : use `reorder`.
- curl tests need both `-c` and `-b` (the session cookie carries the CSRF token).
- Restoring the SQLite db by file copy breaks with WAL files : `db:reset` + bootstrap instead.

## Testing harnesses (keep them in the scratchpad, never in the repo)

- Local OCL repo : `git clone --bare --depth 1 --branch 8.0.0 file://<ocl repo>` + `OCL_REPO_URL`.
- Fake Anthropic server via the client's `base_url`.
- Fake Transifex server (port 7858) via `TRANSIFEX_API_URL`.
- Fake GitHub API via `OCL_GITHUB_API_URL` (+ `OCL_GITHUB_WEB_URL` for the OAuth endpoints).

## Working with the user

- Answer in French (chat, progress lines between tool calls) ; code, comments and commit
  messages stay in English.
- The user commits themselves : never commit, never offer to.
- Never use `git stash` (or any index-touching command) for a baseline.
