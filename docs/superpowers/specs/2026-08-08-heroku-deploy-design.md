# Deploying tictactile to Heroku Cedar (Basic) with a GitHub Actions CI gate

**Date:** 2026-08-08
**Status:** Approved, ready for implementation planning

## Context

tictactile is a portfolio site for an architect/artist. It is a **Sinatra**
application, not Rails: `app/controllers/index.rb` defines 22 static `GET`
routes that render ERB views from hardcoded gallery arrays. There are no
models, no migrations, no seeds, and no tests.

The application has not been modernized since 2019. It pins Ruby 2.5.5 (EOL
March 2021), which no current Heroku stack can build, so deploying it at all
requires a runtime upgrade. It also carries ActiveRecord, `pg`, and a full
test-gem suite that nothing uses.

Historically the site was deployed by pushing from a developer's Windows
machine to a Heroku git remote. That app is gone. This spec covers standing up
a new Heroku app and making `main` on GitHub the source of truth for deploys.

## Goals

1. The app builds and runs on a supported Ruby on a Heroku Cedar Basic dyno.
2. Pushing to `main` deploys automatically, gated on a passing CI check.
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
| Deploy mechanism | Heroku's native GitHub integration | Chosen over an Actions-driven `git push heroku`. No deploy credentials in the repo; no full-history clone (Heroku's git endpoint rejects shallow clones, so a push-based workflow would need `fetch-depth: 0` on a ~380 MB repo). Trade-off accepted: deploy config lives in Heroku's dashboard, not in version control. |
| CI gate | GitHub Actions smoke test | Heroku's "Wait for CI to pass before deploy" keys off GitHub commit statuses. This is where a GitHub Action earns its place in the design. |
| Upgrade scope | Upgrade and strip | ActiveRecord/`pg` serve a database with zero tables; the test gems have no tests. Removing them shrinks the upgrade surface and eliminates a paid Postgres addon. |
| Local Ruby management | chruby + ruby-install | Minimal, no shims, transparent. Reads `.ruby-version` via `auto.sh`. |
| Ruby version | 3.4.9 | Current stable; ahead of Heroku's 3.3.9 default for new apps. |
| Heroku app | New app | The previous app is dead, so there is no cutover risk and no live traffic to protect. |

## Ruby version declaration

One source of truth, three consumers:

- `.ruby-version` contains `3.4.9`. chruby reads it locally; `ruby/setup-ruby`
  reads it in CI via `ruby-version-file`.
- `Gemfile` declares `ruby file: '.ruby-version'` (Bundler 2.3+) instead of
  repeating the literal version.
- `Gemfile.lock`'s `RUBY VERSION` stanza is what the Heroku buildpack actually
  reads, and the locked version takes precedence over everything else. It must
  be committed, and re-locked with `bundle update --ruby` whenever the version
  changes. `bundle platform --ruby` reports what Heroku will use.

Heroku requires a full three-digit version. `~> 3.4.9` is valid; `~> 3.4` is
not.

## Application changes

### Gemfile

From 14 gems to 6:

Gem version pins below are the expected current majors; exact patch versions are
resolved and confirmed at implementation time.

```ruby
source 'https://rubygems.org'
ruby file: '.ruby-version'

gem 'sinatra', '~> 4.1'
gem 'puma',    '~> 6.6'

group :development do
  gem 'sinatra-contrib', '~> 4.1'   # sinatra/reloader only
end

group :test do
  gem 'minitest',  '~> 5.25'
  gem 'rack-test', '~> 2.2'
end
```

Removed: `activerecord`, `activesupport`, `pg`, `rack` (Sinatra 4 pulls Rack 3
itself), `shotgun` (abandoned, Ruby 3 incompatible), `factory_girl` (renamed to
`factory_bot` in 2017), `faker`, `rspec`, `capybara`, `shoulda-matchers`.

Heroku's `BUNDLE_WITHOUT` defaults to `development:test`, so production installs
only Sinatra, Puma, and their dependencies.

### config/puma.rb

Two required fixes:

1. Delete the `rackup DefaultRackup` line. Puma 6 removed that constant; the
   line raises `NameError` on boot.
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
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version-file: .ruby-version
          bundler-cache: true
      - run: bundle exec rake test
```

The workflow must trigger on pushes to `main`, not only on pull requests. Heroku
waits for commit statuses to succeed; if no check ever reports on a `main`
commit, the deploy waits indefinitely rather than failing visibly.

### test/smoke_test.rb

Enumerates `Sinatra::Application.routes['GET']` rather than hardcoding paths, so
all 22 routes are covered and future routes are covered automatically. For each
route: assert a 200 response and a non-empty body. Plus one assertion that an
unknown path returns 404.

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

(Cedar is the default generation; `--generation cedar` is stated explicitly
because Fir now exists. Confirm the flag against the installed CLI version —
the Heroku CLI is not currently installed on this machine.)

Then in the dashboard's Deploy tab:

1. Connect to the `maganeva/tictactile` GitHub repository (requires authorizing
   Heroku's OAuth app against the GitHub account).
2. Enable automatic deploys from `main`.
3. Tick **Wait for CI to pass before deploy**.

No addons. Dropping ActiveRecord means there is no database to provision.

## Rollout

1. Create a branch; apply the application changes.
2. Install the local toolchain: build dependencies (`build-essential`,
   `libssl-dev`, `libyaml-dev`, `zlib1g-dev`, `libffi-dev`, `libreadline-dev`),
   then `ruby-install ruby 3.4.9` into `~/.rubies`, and source `chruby.sh` and
   `auto.sh` from the shell rc.
3. Iterate locally until `bundle exec rake test` is green.
4. Commit the regenerated `Gemfile.lock`; confirm `bundle platform --ruby`
   reports 3.4.9.
5. Push the branch; confirm CI is green.
6. Rebase onto `main` and fast-forward merge (project convention: no merge
   commits). This triggers the first deploy.
7. Watch `heroku logs --tail` through the build, then load the herokuapp.com URL
   and spot-check the home page, one gallery page, and one image.

## Risks and accepted breakage

**The "Music Video 2003" tile will 404.** `app/controllers/index.rb:497`
references `/img/videos/0-rob-d.mp4`, which was purged from git history (it
exceeded GitHub's 100 MB file limit) and now exists only as a local copy at
`../tictactile-stashed/`. Since the deploy source is now the GitHub repo, the
file will not be in the slug. Accepted deliberately; hosting the video
off-repo is the eventual fix.

**No rollback on the first deploy.** A brand-new app has no prior release, so
`heroku rollback` is unavailable until a second release exists. If the first
deploy is broken, the fix is forward.

**Slug size.** `public/img` is 197 MB, giving a slug around 200 MB against
Heroku's 500 MB limit. Builds will take several minutes and every deploy
re-uploads all assets. Not blocking, but it caps how much more media can be
committed to the repo.

**Static asset serving.** Puma serves all 197 MB of images directly. Adequate
for a portfolio site's traffic; the first thing to revisit if response times
disappoint.

**Sinatra 1 to 4 is a four-major-version jump**, alongside Rack 1 to 3. The
three known breakages are enumerated above, but the local loop exists because
others may surface. All 22 routes are static renders, which bounds the risk.
