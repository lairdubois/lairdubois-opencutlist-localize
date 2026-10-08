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
- CodeMirror is vendored in `vendor/javascript` as jsDelivr minified builds (`dist/index.min.js`) :
  `bin/importmap pin` / `update` / `pristine` download unminified files, re-fetch the `.min.js` after.
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
  units included) so pending tool renames / deletions survive a sync. YAML comments (`Unit#note`,
  edited on the key page) are three-way synced too ; baselines without `"note"` fall back to the tool's.
- Rename detection : same fr text, disambiguated by key similarity (trailing segments ×100 +
  leading) ; ambiguous pairs are skipped.
- `Publisher` refuses while the repo fr.yml has unsynced changes ; rewrites quoted key literals in
  js / twig / ruby and warns on leftover dynamic uses. `OclRepo` = shallow checkout in
  `storage/ocl_repo`, force-pushed i18n branch. `GithubAuth` : the publishing admin's GitHub App user
  access token when connected (`GithubOauth`, encrypted on `User`, refreshed under a row lock), else
  App installation tokens (commits / PRs as `<app>[bot]`), else `OCL_GITHUB_TOKEN` ; passed via
  `http.extraHeader` only, git credential helpers and prompts disabled, no push to a remote without
  credentials.
- Base branch (synced with, published from, PR base) = `Setting["base_branch"]`, else `OCL_BASE_BRANCH` :
  chosen on the sync page, saved only when that sync is applied (`OclRepo.base_branch`).
- `Pretranslator` (anthropic gem, `claude-opus-5-5`, structured output) only creates `Suggestion`s,
  never translations.
- Migration : `TransifexImport` (API v3, parallel fetch, keys mapped through the Baseline ;
  ours kept when edited in the tool = conflict), `TransifexRoster` (API exposes no e-mails).
- Text views : CodeMirror 6 (`lib/i18n_text.js` + `i18n_text_controller`) for the translator's editor
  and reference, and on the key page (fr source editor : nothing locked ; translations read-only,
  checked against the source). `Unit.ref_texts` feeds the `$t()` tooltips. Invariants (`{{ var }}`,
  `$t()`, HTML tags, entities) present in the fr source are locked (atomic ranges + transaction
  filter), unknown ones stay editable in red, missing ones are offered as chips. The hidden textarea
  stays the form field, kept in sync ; suggestion buttons fill it and fire `input`. `¶` toggles
  `html.show-ws` (whitespace marks, localStorage). Markdown is highlighted only (markers, link text,
  url ; urls may hold one level of parentheses, e.g. `wiki/STL_(file_format)`).
- Unsaved edits : `dirty-form` flags a form `data-dirty` (fields vs their DOM defaults, `data-dirty-ignore`
  skips one ; `i18n-text:change` covers the editor), `unsaved-guard` on `<body>` asks before a Turbo visit,
  a navigating submit (saves inside a turbo-frame don't navigate) or an unload, and counts them on the
  translations toolbar. Mod-Enter saves, Shift-Mod-Enter saves and approves (`review` target).
- List search (translator's list and keys list) : `shared/_search_bar` + `search_bar_controller` + `ListFilters`.
  `q` searches the texts only ; `status[]` (untranslated / outdated / unreviewed / reviewed, a partition) is
  OR-ed, `questions=1` AND-ed ; `key`, `prefix`, `at` are chips with their own input ; a single `at` index (no `-`) is exclusive (applying
  it drops the others, any other change drops it ; enforced by `ListFilters` too, and the menu's counts leave it out). Every change submits
  the GET form ; Mod-F focuses `q` (pressed again in it : the browser's find), Esc blurs it and the chips' inputs, Shift-Esc in them resets the search ; Enter
  and Shift-Esc keep the focus in the field across the Turbo visit (sessionStorage flag) ; on Enter, `#120` / `#120-180`,
  `key:…`, `branch:…` words of `q` move to their chip ; the menu shows each entry's count under the other filters.
- The site header is sticky (`h-14` + 1px border) ; the translations toolbar sticks below it with
  `top-[calc(3.5rem+1px)]` : keep both in sync if the header height changes.

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
- CodeMirror rewrites its root element's `class` attribute (e.g. on focus) : pass classes through
  `EditorView.editorAttributes` (`className` option), never `classList.add`. Don't set a font size in
  the CM theme either : it beats the Tailwind `text-sm` on the same element.
- Login in curl tests : `User#generate_token_for(:login)` via `rails runner`, then GET + POST
  `/login/<token>` (the dev login form is rate limited to 5 per 10 min).

## Testing harnesses (keep them in the scratchpad, never in the repo)

- Local OCL repo : `git clone --bare --depth 1 --branch 8.0.0 file://<ocl repo>` + `OCL_REPO_URL`.
- Fake Anthropic server via the client's `base_url`.
- Fake Transifex server (port 7858) via `TRANSIFEX_API_URL`.
- Fake GitHub API via `OCL_GITHUB_API_URL` (+ `OCL_GITHUB_WEB_URL` for the OAuth endpoints).
- Editor JS without a browser : Node + jsdom, vendored CodeMirror files copied into a scratch
  `node_modules` (one package dir per bare specifier, `"type": "module"`) ; `npm i` prunes them.
  Expose jsdom's `window`, `document`, `Window`… as globals before importing the module.

## Working with the user

- Answer in French (chat, progress lines between tool calls) ; code, comments and commit
  messages stay in English.
- The user commits themselves : never commit, never offer to.
- Never use `git stash` (or any index-touching command) for a baseline.
