# Deploying tictactile to Heroku Cedar (Basic) with a GitHub Actions CI gate

**Date:** 2026-08-08
**Status:** Approved, ready for implementation planning

## Context

tictactile is a portfolio site for an architect/artist. It is a **Sinatra**
application, not Rails: `app/controllers/index.rb` defines 20 `GET` route
declarations that render ERB views from hardcoded gallery arrays. Two are exact
duplicates that Sinatra never reaches, so there are 18 reachable paths. There
are no models, no migrations, no seeds, and no tests.

The application has not been modernized since 2019. It pins Ruby 2.5.5 (EOL
March 2021), which no current Heroku stack can build, so deploying it at all
requires a runtime upgrade. It also carries ActiveRecord, `pg`, and a full
test-gem suite that nothing uses.

Historically the site was deployed by pushing from a developer's Windows
machine to a Heroku git remote. That app is gone. This spec covers standing up
a new Heroku app and making `main` on GitHub the source of truth for deploys.

## Goals

1. The app builds and runs on a supported Ruby on a Heroku Cedar Basic dyno.
2. Deploying is one repeatable command from a checkout of `main`, run once CI on
   that commit is green.
3. Dead weight (database layer, unused test harness, abandoned gems) is removed
   rather than upgraded.

## Non-goals

- Pointing `tictactile.net` at the new app. Deferred; the app will serve on its
  `herokuapp.com` URL. Domain cutover is a separate follow-up.
- Restoring the `0-rob-d.mp4` video. See "Accepted breakage" below.
- Any change to the site's content, layout, routes, or gallery data.
- Moving static assets to a CDN or object storage.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Deploy mechanism | `git push heroku main` from a local checkout | Forced by a permissions wall (see below). Needs no GitHub permissions at all, since GitHub is not in the deploy path. Trade-off accepted: deploys are manual, so nothing mechanically prevents deploying a commit whose CI is red. |
| CI gate | GitHub Actions smoke test, checked before deploying | Runs on pull requests and on pushes to `main`. With the integration route gone it is an advisory gate rather than an enforced one: the deploy procedure requires confirming the check is green on the commit being deployed. |
| Upgrade scope | Upgrade and strip | ActiveRecord/`pg` serve a database with zero tables; the test gems have no tests. Removing them shrinks the upgrade surface and eliminates a paid Postgres addon. |
| Local Ruby management | chruby + ruby-install | Minimal, no shims, transparent. Reads `.ruby-version` via `auto.sh`. |
| Ruby version | 3.4.10 | Current stable; ahead of Heroku's 3.3.9 default for new apps. |
| Heroku app | New app | The previous app is dead, so there is no cutover risk and no live traffic to protect. |

## Ruby version declaration

One source of truth, three consumers:

- `.ruby-version` contains `3.4.10`. chruby reads it locally; `ruby/setup-ruby`
  reads it in CI via `ruby-version-file`.
- `Gemfile` declares `ruby file: '.ruby-version'` (Bundler 2.3+) instead of
  repeating the literal version.
- `Gemfile.lock`'s `RUBY VERSION` stanza is what the Heroku buildpack actually
  reads, and the locked version takes precedence over everything else. It must
  be committed, and re-locked with `bundle update --ruby` whenever the version
  changes. `bundle platform --ruby` reports what Heroku will use.

Heroku requires a full three-digit version. `~> 3.4.10` is valid; `~> 3.4` is
not.

## Application changes

### Gemfile

From 14 gems to 6:

Pins below are the current released versions as of 2026-08-08, confirmed against
the RubyGems API.

```ruby
source 'https://rubygems.org'
ruby file: '.ruby-version'

gem 'sinatra', '~> 4.2'
gem 'puma',    '~> 8.0'

group :development do
  gem 'sinatra-contrib', '~> 4.2'   # sinatra/reloader only
end

group :test do
  gem 'minitest',  '~> 6.0'
  gem 'rack-test', '~> 2.2'
  gem 'rake',      '~> 13.4'
end
```

Removed: `activerecord`, `activesupport`, `pg`, `rack` (Sinatra 4 pulls Rack 3
itself), `shotgun` (abandoned, Ruby 3 incompatible), `factory_girl` (renamed to
`factory_bot` in 2017), `faker`, `rspec`, `capybara`, `shoulda-matchers`.

Heroku's `BUNDLE_WITHOUT` defaults to `development:test`, so production installs
only Sinatra, Puma, and their dependencies.

### config/puma.rb

Two required fixes:

1. Delete the `rackup DefaultRackup` line. Puma removed that constant in 6.0 and
   we are installing 8.x, so the line raises `NameError` on boot.
2. Replace `workers Integer(ENV['WEB_CONCURRENCY'] || 16)` and 32 threads with
   2 workers and 5 threads. A Basic dyno has 512 MB of RAM; 16 preloaded Puma
   workers will trigger R14/R15 memory errors immediately. Both stay
   overridable by config var.

### config/environment.rb

- Remove `require 'pg'` and `require 'active_record'`.
- Remove `require APP_ROOT.join('config', 'database')`.
- Remove `enable :sessions` and `set :session_secret`. Sinatra 4 on Rack 3
  enforces a minimum session secret length, and the current value is a
  22-character placeholder. Nothing in the app uses sessions — there are no
  forms and no authentication — so the feature is removed rather than fixed.
- Replace `File.exists?` with `File.exist?` (deprecated alias).
- Keep: `set :root`, `set :views`, the controller/helper autoload loop, and
  `require 'sinatra/reloader' if development?`.

### Files deleted

- `config/database.rb`
- `db/` (contains only an empty `seeds.rb` and `db/migrate/.gitkeep`)
- `app/models/` (contains only `.gitkeep`)
- The `Rakefile`'s `generate:*` and `db:*` namespaces — untouched Dev Bootcamp
  scaffolding. The Rakefile is replaced with a minitest task.

### Unchanged

`app/controllers/index.rb`, all ERB views, all of `public/`, and the `Procfile`
(`web: bundle exec puma -C config/puma.rb` remains correct).

## CI gate

`.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version-file: .ruby-version
          bundler-cache: true
      - run: bundle exec rake test
```

The workflow triggers on pushes to `main` as well as on pull requests. That
trigger was originally mandatory because Heroku's integration waited for commit
statuses on the deploy branch. With deploys now driven from the CLI, it remains
worth keeping: it is what lets you confirm `main` is green before pushing to
Heroku, rather than inferring it from the PR that preceded the merge.

### test/smoke_test.rb

Enumerates `Sinatra::Application.routes['GET']` rather than hardcoding paths, so
all 18 unique routes are covered and future routes are covered automatically. For
each route: follow any redirects to their destination, then assert a 200 response
and a non-empty body. Plus one assertion that an unknown path returns 404.

Following redirects is required, not incidental: 14 of the route declarations are
`redirect(..., 301)` URL canonicalizations to a trailing-slash twin. Asserting a
flat 200 would fail on all of them; accepting a bare 301 without following it
would let a redirect pointing at a dead page pass the gate. A five-hop cap turns
a redirect loop into a clear failure rather than a hang.

The test is deliberately shallow. Its job is to catch this upgrade's actual
risks — Rack 3 breaking ERB rendering, or a removed gem still being required at
boot — not to test site content.

## Heroku setup

One-time, performed manually:

```bash
heroku create tictactile-web --generation cedar
heroku ps:type basic --app tictactile-web
heroku config:set RACK_ENV=production WEB_CONCURRENCY=2 --app tictactile-web
```

Then add the Heroku git remote, which is the deploy path:

```bash
heroku git:remote --app tictactile-web
```

No addons. Dropping ActiveRecord means there is no database to provision.

### Why not Heroku's GitHub integration

The original design used Heroku's native GitHub integration with "Wait for CI to
pass before deploy". It is not achievable for this repository:

- Heroku's integration installs a repository webhook, and GitHub permits only
  repo **admins** to create webhooks.
- `maganeva` is a **personal** GitHub account, not an organization. Personal
  repositories have no admin role for collaborators — admin belongs solely to the
  owner. `joewalp` is a collaborator with `push` but `admin: false`, and no
  setting change can lift that.
- Authorizing Heroku's OAuth app as `maganeva` requires MFA through an email
  account that is not currently accessible.

Transferring the repo to an organization would restore the option, since org
repos support an admin role for collaborators. That is a larger change than this
work justifies.

Note that the same wall blocks an Actions-driven deploy: adding the
`HEROKU_API_KEY` repository secret that approach needs also requires repo admin.

### Deploy procedure

```bash
git checkout main && git pull
gh pr checks   # or: gh run list --branch main --limit 1
git push heroku main
```

The CI check is advisory here rather than enforced — confirming it is green
before pushing to Heroku is a step in the procedure, not something the platform
guarantees. This is the cost of the permissions wall, and it is the single
meaningful regression against the original design.

## Rollout

1. Create a branch; apply the application changes.
2. Install the local toolchain: build dependencies (`build-essential`,
   `libssl-dev`, `libyaml-dev`, `zlib1g-dev`, `libffi-dev`, `libreadline-dev`),
   then `ruby-install ruby 3.4.10` into `~/.rubies`, and source `chruby.sh` and
   `auto.sh` from the shell rc.
3. Iterate locally until `bundle exec rake test` is green.
4. Commit the regenerated `Gemfile.lock`; confirm `bundle platform --ruby`
   reports 3.4.10.
5. Push the branch; confirm CI is green.
6. Rebase onto `main` and fast-forward merge (project convention: no merge
   commits). This triggers the first deploy.
7. Watch `heroku logs --tail` through the build, then load the herokuapp.com URL
   and spot-check the home page, one gallery page, and one image.

## Risks and accepted breakage

**The "Music Video 2003" tile will 404.** ~~`app/controllers/index.rb:497`
references `/img/videos/0-rob-d.mp4`, which was purged from git history (it
exceeded GitHub's 100 MB file limit) and now exists only as a local copy at
`../tictactile-stashed/`. Since the deploy source is now the GitHub repo, the
file will not be in the slug.~~ **Resolved 2026-08-09** by committing the file
as chunks and reassembling at boot — see
[2026-08-09-rob-d-video-design.md](2026-08-09-rob-d-video-design.md). Note that
this spec expected off-repo hosting to be the fix; it was not, and slug size is
now ~380 MB of the 500 MB limit.

**No rollback on the first deploy.** A brand-new app has no prior release, so
`heroku rollback` is unavailable until a second release exists. If the first
deploy is broken, the fix is forward.

**Deploying is manual, so it can be skipped or forgotten.** Merging to `main` no
longer ships anything by itself. Whoever merges must also push to Heroku, and
must check CI first. A red commit can reach production if that step is skipped —
the platform will not stop it.

**Slug size.** `public/img` is 197 MB, giving a slug around 200 MB against
Heroku's 500 MB limit. Builds will take several minutes and every deploy
re-uploads all assets. Not blocking, but it caps how much more media can be
committed to the repo. Updated 2026-08-09: the committed video chunks add
~183 MB, bringing the slug to roughly 380 MB. The remaining headroom is now
small enough that the next large asset will force the move to off-repo
hosting.

**Static asset serving.** Puma serves all 197 MB of images directly. Adequate
for a portfolio site's traffic; the first thing to revisit if response times
disappoint.

**Sinatra 1 to 4 is a four-major-version jump**, alongside Rack 1 to 3. The
three known breakages are enumerated above, but the local loop exists because
others may surface. All 18 routes are static renders, which bounds the risk.
