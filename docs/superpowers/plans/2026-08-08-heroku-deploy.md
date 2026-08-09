# Heroku Deploy with CI Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get tictactile building and serving on a Heroku Cedar Basic dyno, deployed automatically from `main` on GitHub and gated on a passing GitHub Actions smoke test.

**Architecture:** A Sinatra 4 / Rack 3 app on Ruby 3.4.10, with the unused ActiveRecord layer and test-gem suite removed. A minitest smoke test enumerates the app's own routing table and asserts every reachable route returns 200; GitHub Actions runs it on every push to `main` and posts a commit status. Heroku's native GitHub integration watches `main` and deploys only when that status is green. No deploy credentials live in the repo.

**Tech Stack:** Ruby 3.4.10 (chruby + ruby-install), Sinatra 4.2, Puma 8.0, Rack 3.2, Minitest 6.0, Rack::Test 2.2, GitHub Actions, Heroku Cedar.

**Spec:** `docs/superpowers/specs/2026-08-08-heroku-deploy-design.md`

## Global Constraints

- Ruby version is `3.4.10`, declared once in `.ruby-version`; the Gemfile reads it via `ruby file: '.ruby-version'` (requires Bundler 2.3+).
- `Gemfile.lock` must be committed. Its `RUBY VERSION` stanza is what Heroku reads, and the locked version takes precedence over all other declarations.
- Heroku requires a full three-digit Ruby version. `~> 3.4.10` is valid; `~> 3.4` is not.
- Production gem set is Sinatra + Puma only. Heroku's `BUNDLE_WITHOUT` defaults to `development:test`.
- Basic dyno has 512 MB RAM. Puma must not exceed 2 workers by default.
- Do not modify `app/controllers/index.rb`, any ERB view, or anything under `public/`.
- Branch for all work: `heroku-deploy`. Never commit directly to `main`.
- Commit messages end with the project's `Co-Authored-By` / `Claude-Session` trailers as configured.

## File Structure

| File | Disposition | Responsibility |
|---|---|---|
| `.ruby-version` | Modify | Single source of truth for the Ruby version |
| `Gemfile` | Rewrite | Declares the 6-gem dependency set; reads `.ruby-version` |
| `Gemfile.lock` | Regenerate | Locked resolution, including `RUBY VERSION` for Heroku |
| `config/environment.rb` | Modify | App boot: requires, Sinatra config, controller loading |
| `config/puma.rb` | Rewrite | Web server config sized for a 512 MB dyno |
| `config/database.rb` | Delete | ActiveRecord connection for a database with no tables |
| `db/` | Delete | Empty seeds + empty migrations dir |
| `app/models/` | Delete | Contains only `.gitkeep` |
| `Rakefile` | Rewrite | Was DB/generator scaffolding; becomes a minitest task |
| `test/smoke_test.rb` | Create | Asserts every reachable route returns 200 |
| `.github/workflows/ci.yml` | Create | Runs the smoke test, posts the commit status Heroku gates on |
| `README.md` | Modify | Replaces dev instructions that reference a dead Heroku remote |

---

### Task 1: Local Ruby 3.4.10 toolchain and dependency rewrite

Installs chruby + ruby-install, builds Ruby 3.4.10, and rewrites the dependency declarations. Everything downstream needs a working `bundle`, so this task carries the setup.

**Files:**
- Modify: `.ruby-version`
- Modify: `Gemfile` (full rewrite)
- Regenerate: `Gemfile.lock`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: a working `bundle exec` on Ruby 3.4.10; gems `sinatra ~> 4.2`, `puma ~> 8.0`, `sinatra-contrib ~> 4.2` (development), `minitest ~> 6.0` and `rack-test ~> 2.2` (test)

- [ ] **Step 1: Install build dependencies**

Ruby 3.4 needs libyaml for psych; omitting it produces a Ruby that cannot `require 'yaml'`.

```bash
sudo apt-get update
sudo apt-get install -y build-essential libssl-dev libyaml-dev zlib1g-dev \
  libffi-dev libreadline-dev libgdbm-dev bison curl
```

- [ ] **Step 2: Install ruby-install 0.10.2**

```bash
cd /tmp
curl -fsSL -o ruby-install-0.10.2.tar.gz \
  https://github.com/postmodern/ruby-install/releases/download/v0.10.2/ruby-install-0.10.2.tar.gz
tar -xzf ruby-install-0.10.2.tar.gz
cd ruby-install-0.10.2
sudo make install
ruby-install --version
```

Expected: prints `ruby-install: 0.10.2`.

- [ ] **Step 3: Install chruby 0.3.9**

```bash
cd /tmp
curl -fsSL -o chruby-0.3.9.tar.gz \
  https://github.com/postmodern/chruby/releases/download/v0.3.9/chruby-0.3.9.tar.gz
tar -xzf chruby-0.3.9.tar.gz
cd chruby-0.3.9
sudo make install
```

- [ ] **Step 4: Build Ruby 3.4.10**

`--update` refreshes ruby-install's known-versions list so 3.4.10 resolves. The build takes several minutes.

```bash
ruby-install --update
ruby-install ruby 3.4.10
```

Expected: ends with `>>> Successfully installed ruby 3.4.10 into /home/joe/.rubies/ruby-3.4.10`.

- [ ] **Step 5: Wire chruby into the shell**

Append to `~/.zshrc` (the user's shell is zsh). `auto.sh` is what makes chruby honour `.ruby-version`; without it chruby is manual-only.

```bash
cat >> ~/.zshrc <<'RC'

# chruby — Ruby version management
source /usr/local/share/chruby/chruby.sh
source /usr/local/share/chruby/auto.sh
RC
```

- [ ] **Step 6: Set the project Ruby version**

```bash
cd /home/joe/dev/tictactile
echo '3.4.10' > .ruby-version
```

- [ ] **Step 7: Verify auto-switching works**

Open a new shell (or `source ~/.zshrc`), then:

```bash
cd /home/joe/dev/tictactile && ruby --version
```

Expected: `ruby 3.4.10 (...) [x86_64-linux]`. If it still reports "command not found", `auto.sh` was not sourced — re-check Step 5 before continuing.

- [ ] **Step 8: Rewrite the Gemfile**

Replace the entire contents of `Gemfile` with:

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

`rake` is required because `bundle exec rake test` is the verification command
for Task 2, Task 3, and the CI workflow. It belongs in `:test` because Heroku's
`BUNDLE_WITHOUT` defaults to `development:test` and production never runs rake.

- [ ] **Step 9: Regenerate the lockfile**

The existing `Gemfile.lock` is locked to Ruby 2.5.5 and Bundler 2.0.1. Delete it so the resolution is clean rather than patched.

```bash
cd /home/joe/dev/tictactile
rm Gemfile.lock
gem install bundler
bundle install
```

Expected: resolves without error. No `pg` build step should occur — if you see one, the Gemfile edit did not take.

- [ ] **Step 10: Verify the version Heroku will use**

```bash
bundle platform --ruby
```

Expected: `ruby 3.4.10`. This is the single most important verification in the task — if this disagrees with `.ruby-version`, Heroku will build the wrong Ruby.

- [ ] **Step 11: Commit**

```bash
git add .ruby-version Gemfile Gemfile.lock
git commit -m "chore: upgrade to Ruby 3.4.10 and Sinatra 4"
```

---

### Task 2: Smoke test harness (failing)

Writes the test first. It is expected to fail at boot, because `config/environment.rb` still requires `pg` and `active_record`, which Task 1 removed from the bundle. That failure is the point: it proves the test actually exercises app boot.

**Files:**
- Create: `test/smoke_test.rb`
- Rewrite: `Rakefile`

**Interfaces:**
- Consumes: the gem set from Task 1
- Produces: `bundle exec rake test` as the single verification command used by Task 3, Task 5, and CI

- [ ] **Step 1: Write the Rakefile**

Replace the entire contents of `Rakefile` with:

```ruby
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = false
end

task default: :test
```

- [ ] **Step 2: Write the smoke test**

Create `test/smoke_test.rb`:

```ruby
ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require_relative '../config/environment'

# Classic-style Sinatra boots a server at_exit when it thinks it is the main
# script. Under Rake it is not, but being explicit costs nothing.
Sinatra::Application.set :run, false

class SmokeTest < Minitest::Test
  include Rack::Test::Methods

  # Sinatra stores routes as { verb => [[pattern, conditions, wrapper], ...] }.
  # Mustermann patterns stringify back to their original route literal.
  def self.reachable_paths
    Sinatra::Application.routes.fetch('GET', [])
                        .map { |route| route[0].to_s }
                        .uniq
  end

  def app
    Sinatra::Application
  end

  def test_routing_table_loaded
    count = self.class.reachable_paths.size
    assert_operator count, :>=, 18,
                    "expected at least 18 GET routes, found #{count} — did the controller fail to load?"
  end

  reachable_paths.each do |path|
    define_method("test_get_#{path.gsub(/[^a-zA-Z0-9]/, '_')}") do
      get path

      hops = 0
      while last_response.redirect?
        hops += 1
        assert_operator hops, :<=, 5,
                        "GET #{path} exceeded 5 redirects — possible redirect loop"
        follow_redirect!
      end

      assert_equal 200, last_response.status,
                   "GET #{path} ended at #{last_request.path} with #{last_response.status}"
      refute_empty last_response.body.strip,
                   "GET #{path} ended at #{last_request.path} with an empty body"
    end
  end

  def test_unknown_path_returns_404
    get '/definitely-not-a-real-page'
    assert_equal 404, last_response.status
  end
end
```

`test_routing_table_loaded` guards against the vacuous case: if the controller failed to load, `reachable_paths` would be empty, zero per-route tests would be generated, and the suite would pass while testing nothing.

- [ ] **Step 3: Run the test and verify it fails**

```bash
bundle exec rake test
```

Expected: FAIL during load, raised from `config/environment.rb`. The first error encountered is `NoMethodError: undefined method 'exists?' for class File` at `config/environment.rb:6` — `File.exists?` was removed in modern Ruby and that line runs before the `require 'pg'` on line 14, so the pg `LoadError` is never reached. Either way the suite fails at app boot, which is the point: it proves the test exercises boot. Task 3 fixes both causes at once.

If it fails for some third reason, stop and investigate — that would mean a problem this plan does not anticipate.

- [ ] **Step 4: Commit the failing test**

```bash
git add Rakefile test/smoke_test.rb
git commit -m "test: add route smoke test and minitest rake task"
```

---

### Task 3: Strip the database layer

Makes the Task 2 test pass by removing the ActiveRecord/Postgres layer the app never used.

**Files:**
- Modify: `config/environment.rb`
- Delete: `config/database.rb`, `db/seeds.rb`, `db/migrate/.gitkeep`, `app/models/.gitkeep`

**Interfaces:**
- Consumes: `bundle exec rake test` from Task 2
- Produces: an app that boots with only Sinatra and Puma loaded; `APP_ROOT` remains defined (the controller loader uses it), `APP_NAME` and `DB_NAME` are gone

- [ ] **Step 1: Rewrite config/environment.rb**

Replace the entire contents with:

```ruby
# Set up gems listed in the Gemfile.
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../Gemfile', __FILE__)

require 'bundler/setup' if File.exist?(ENV['BUNDLE_GEMFILE'])

require 'pathname'

require 'sinatra'
require 'sinatra/reloader' if development?

require 'erb'

# Some helper constants for path-centric logic
APP_ROOT = Pathname.new(File.expand_path('../../', __FILE__))

configure do
  # By default, Sinatra assumes that the root is the file that calls the
  # configure block. Since this is not the case for us, we set it manually.
  set :root, APP_ROOT.to_path

  # Set the views to app/views
  set :views, File.join(Sinatra::Application.root, 'app', 'views')
end

# Set up the controllers and helpers
Dir[APP_ROOT.join('app', 'controllers', '*.rb')].each { |file| require file }
Dir[APP_ROOT.join('app', 'helpers', '*.rb')].each { |file| require file }
```

Changes from the original, all deliberate:
- dropped `require 'pg'`, `require 'active_record'`, `require 'logger'`, `require 'uri'`, `require 'rubygems'` (unnecessary since Ruby 1.9) and the `config/database` require
- dropped `APP_NAME`, which only existed to build a database name
- dropped `enable :sessions` and `set :session_secret` — Sinatra 4 on Rack 3 enforces a minimum secret length, and nothing in the app uses sessions
- `File.exists?` → `File.exist?` (deprecated alias)

- [ ] **Step 2: Delete the database layer**

```bash
cd /home/joe/dev/tictactile
git rm config/database.rb
git rm -r db
git rm app/models/.gitkeep
```

- [ ] **Step 3: Run the test and verify it passes**

```bash
bundle exec rake test
```

Expected: PASS, with at least 20 tests (18 route tests + the routing-table guard + the 404 test). If a route returns 500, read the stack trace — this is the Rack 3 / Sinatra 4 breakage the test exists to catch.

- [ ] **Step 4: Commit**

```bash
git add config/environment.rb
git commit -m "refactor: remove unused ActiveRecord and Postgres layer"
```

---

### Task 4: Fix Puma configuration for a Basic dyno

The smoke test uses Rack::Test and never starts Puma, so this needs its own verification: actually boot the server and request a page.

**Files:**
- Rewrite: `config/puma.rb`

**Interfaces:**
- Consumes: the app from Task 3
- Produces: a Puma config that boots under Puma 8 and fits in 512 MB; reads `WEB_CONCURRENCY` (default 2) and `MAX_THREADS` (default 5)

- [ ] **Step 1: Rewrite config/puma.rb**

Replace the entire contents with:

```ruby
# Sized for a Heroku Basic dyno (512 MB RAM). Raising WEB_CONCURRENCY without
# raising the dyno size will produce R14/R15 memory errors.
workers Integer(ENV.fetch('WEB_CONCURRENCY', 2))

threads_count = Integer(ENV.fetch('MAX_THREADS', 5))
threads threads_count, threads_count

preload_app!

port        ENV.fetch('PORT', 3000)
environment ENV.fetch('RACK_ENV', 'development')
```

Removed from the original:
- `rackup DefaultRackup` — Puma removed that constant in 6.0; on Puma 8 it raises `NameError` at boot
- the `unless Gem.win_platform?` guard on `workers` — the app no longer runs on Windows
- two commented-out `on_worker_boot` blocks that re-established ActiveRecord connections
- default of 16 workers / 32 threads, which cannot fit in 512 MB

- [ ] **Step 2: Boot the server**

In one terminal:

```bash
cd /home/joe/dev/tictactile
RACK_ENV=production PORT=3000 bundle exec puma -C config/puma.rb
```

Expected: Puma reports `Use Ctrl-C to stop` and `* Workers: 2`. A `NameError` here means the `rackup` line survived the rewrite.

- [ ] **Step 3: Verify it serves**

In a second terminal:

```bash
curl -sL -o /dev/null -w '%{http_code}\n' http://localhost:3000/
curl -sL -o /dev/null -w '%{http_code}\n' http://localhost:3000/amphibians
curl -sL -o /dev/null -w '%{http_code}\n' http://localhost:3000/img/videos/haiku-th.jpg
```

Expected: `200` three times. Note the `-L`: `/amphibians` is one of the 14 routes that issues a `redirect(..., 301)` to its trailing-slash twin, so without following redirects it reports `301`, not `200`. The third check confirms static asset serving out of `public/` still resolves after the `set :root` handling changed. Stop the server with Ctrl-C.

- [ ] **Step 4: Commit**

```bash
git add config/puma.rb
git commit -m "fix: size Puma for a 512MB Basic dyno and drop removed DefaultRackup"
```

---

### Task 5: GitHub Actions CI gate

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `bundle exec rake test` from Task 2
- Produces: a commit status named `smoke` on every push to `main` and on pull requests, checked by hand before each deploy in Task 7

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/ci.yml`:

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

`ruby-version-file` reads the same `.ruby-version` chruby uses, so local and CI cannot drift. `bundler-cache: true` runs `bundle install` and caches the result.

The `push.branches: [main]` trigger was originally mandatory because Heroku's GitHub integration waited for commit statuses on the deploy branch. That integration is not available for this repo (see Task 6), so deploys are manual — but keep the trigger. It is what lets you confirm `main` itself is green before pushing to Heroku, instead of inferring it from the PR that preceded the merge.

- [ ] **Step 2: Push the branch and open a PR**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add smoke test workflow"
git push -u origin heroku-deploy
gh pr create --fill --base main
```

- [ ] **Step 3: Verify CI passes on the PR**

```bash
gh pr checks --watch
```

Expected: the `smoke` check reports success. If `bundle install` fails in CI but worked locally, the likely cause is `Gemfile.lock` not being committed — confirm with `git show HEAD --stat`.

---

### Task 6: Create the Heroku app and add the deploy remote

Manual infrastructure work. Nothing here is committed to the repo.

**Files:** none

**Interfaces:**
- Consumes: the green `smoke` check from Task 5
- Produces: a Heroku app plus a `heroku` git remote, which is the deploy path used in Task 7

> **Revised mid-execution.** This task originally connected Heroku's native
> GitHub integration for automatic deploys. That route is unavailable: Heroku's
> integration installs a repository webhook, GitHub allows only repo **admins**
> to create webhooks, and `maganeva` is a personal account whose repositories
> have no admin role for collaborators — `joewalp` has `push` but `admin: false`.
> Authorizing Heroku's OAuth app as `maganeva` requires MFA through an
> inaccessible email account. Deploys therefore run from the Heroku CLI.
> The same wall blocks an Actions-driven deploy, which would need a
> `HEROKU_API_KEY` repository secret — also admin-gated.

- [ ] **Step 1: Install the Heroku CLI**

Not currently installed on this machine.

```bash
curl https://cli-assets.heroku.com/install.sh | sh
heroku --version
```

- [ ] **Step 2: Log in**

This opens a browser; the user must complete it interactively. Suggest they run it themselves with `! heroku login`.

```bash
heroku login
```

- [ ] **Step 3: Create the app**

```bash
heroku create tictactile-web
```

Verified against the installed CLI (heroku/11.9.0): there is **no** `--generation`
flag — `heroku create` offers `--stack` but not `--generation`. Cedar is what this
command produces. If the app name is taken, pick another and use it consistently
for the rest of the task.

- [ ] **Step 4: Set the config vars**

```bash
heroku config:set RACK_ENV=production WEB_CONCURRENCY=2 --app tictactile-web
```

**Do not run `heroku ps:type basic` here.** Process types are created by the first
deploy, so before one exists the command fails with "No process types on
tictactile-web. Upload a Procfile to add process types." Setting the dyno type
moves to Task 7, immediately after the first release. This ordering was verified
against a real app, not assumed.

`heroku ps:type basic` incurs charges (Basic is a paid plan). Confirm with the user before running if that has not already been agreed.

- [ ] **Step 5: Add the Heroku git remote**

This replaces the dashboard GitHub connection. It is the deploy path.

```bash
heroku git:remote --app tictactile-web
git remote -v
```

Expected: a `heroku` remote pointing at `https://git.heroku.com/tictactile-web.git`, alongside the existing `origin`.

- [ ] **Step 6: Verify no addons were provisioned**

```bash
heroku addons --app tictactile-web
```

Expected: `No add-ons for app tictactile-web.` Dropping ActiveRecord means there is no database to pay for.

---

### Task 7: Update the README and ship

The README currently instructs the reader to open a Windows "Command Prompt with Ruby and Rails", edit in Sublime, and `git pull heroku master` from an app that no longer exists. Every one of those instructions is now wrong, and the deploy model has changed. This is documentation for the thing this plan changed, not unrelated cleanup.

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above, including the `heroku` git remote from Task 6
- Produces: the merge to `main`, followed by the first deploy pushed by hand

- [ ] **Step 1: Replace the development section of README.md**

Keep the existing intro lines (the site description and the tictactile.net link). Replace everything from `### development` onward with:

````markdown
### development

Requires Ruby 3.4.10, managed with [chruby](https://github.com/postmodern/chruby)
and [ruby-install](https://github.com/postmodern/ruby-install). The version is
pinned in `.ruby-version` and picked up automatically by chruby's `auto.sh`.

```bash
ruby-install ruby 3.4.10   # first time only
cd tictactile              # chruby switches automatically
bundle install
bundle exec puma -C config/puma.rb
```

The site is then at http://localhost:3000.

Run the smoke tests, which check that every route still renders:

```bash
bundle exec rake test
```

### deployment

Deploys are manual, from a local checkout of `main`:

```bash
git checkout main && git pull
gh run list --branch main --limit 1   # confirm the smoke check is green
git push heroku main
```

GitHub Actions runs the smoke test on every pull request and every push to
`main`, but nothing enforces it at deploy time — checking it is a step in the
procedure. See `docs/superpowers/specs/2026-08-08-heroku-deploy-design.md` for
why Heroku's automatic GitHub deploys are not available for this repository.

Note: `public/img/videos/0-rob-d.mp4` is not in the repository (it exceeds
GitHub's 100 MB file limit), so the "Music Video 2003" entry does not play in
production.
````

- [ ] **Step 2: Commit and push**

```bash
git add README.md
git commit -m "docs: replace stale dev instructions with chruby setup"
git push
```

- [ ] **Step 3: Confirm CI is still green**

```bash
gh pr checks --watch
```

- [ ] **Step 4: Merge to main by rebase**

Project convention is rebase, never a merge commit.

```bash
git checkout main
git pull
git rebase main heroku-deploy
git checkout main
git merge --ff-only heroku-deploy
git push
```

If the rebase conflicts, stop and surface each conflict for the user to resolve rather than guessing.

- [ ] **Step 4b: Confirm CI is green on the `main` commit itself**

The merge pushes `main`, which fires the workflow's `push` trigger for the first
time. This is also the first exercise of that trigger, so confirm a check
actually appears — deploying is gated on it by procedure, not by the platform.

```bash
gh run list --branch main --limit 3
gh run watch
```

Expected: a `CI` run on the `main` commit, event `push`, concluding `success`. If no run appears at all, stop — the `push.branches: [main]` trigger is not working, and every future deploy would be unverified.

- [ ] **Step 5: Deploy**

```bash
git push heroku main
```

This is the deploy. Expect several minutes: the push transfers ~380 MB of history, then Heroku builds the slug. Watch the build output for `Building on Heroku-24`, `Installing dependencies using bundler`, the detected Ruby version (should read 3.4.10), `Compressing`, and `Launching`.

- [ ] **Step 5a: Watch the dyno come up**

```bash
heroku logs --tail --app tictactile-web
```

Expected sequence: `Building on Heroku-24`, `Installing dependencies using bundler`, `Compressing`, `Launching`, then `State changed from starting to up`. Watch for `Ruby version change detected` confirming 3.4.10.

- [ ] **Step 5b: Confirm the dyno type**

```bash
heroku ps --app tictactile-web
```

Expected: `=== web (Basic): bundle exec puma -C config/puma.rb (1)` and `web.1: up`.

**Verified on the real deploy: `heroku ps:type basic` is not needed.** The `web`
dyno came up as Basic automatically on the first release — the scale event fires
as part of the deploy, not as a separate command. Earlier drafts of this plan ran
`ps:type basic` in Task 6 (where it fails, since no process type exists yet) and
then here; neither was necessary. Basic is a paid plan, so if `heroku ps` reports
some other type, changing it requires the user's explicit authorization first.

- [ ] **Step 6: Verify the live site**

The real hostname carries a generated suffix — `heroku create` reported
`https://tictactile-web-b7da95331725.herokuapp.com/`, not the bare
`tictactile-web.herokuapp.com` this plan originally assumed. Confirm it with
`heroku apps:info --app tictactile-web` before substituting below.

```bash
APP_URL=https://tictactile-web-b7da95331725.herokuapp.com
curl -sL -o /dev/null -w '%{http_code}\n' $APP_URL/
curl -sL -o /dev/null -w '%{http_code}\n' $APP_URL/equil
curl -sL -o /dev/null -w '%{http_code}\n' $APP_URL/img/videos/haiku-th.jpg
```

Expected: `200` three times. Note `-L` again — `/equil` is one of the 301 canonicalization routes. Then open the site in a browser and confirm the home page renders with images.

Known and accepted: `$APP_URL/img/videos/0-rob-d.mp4` returns 404. That is the deliberate breakage recorded in the spec.

- [ ] **Step 7: Delete the branch**

```bash
git branch -d heroku-deploy
git push origin --delete heroku-deploy
```

---

## Out of scope (recorded, not planned)

These are named in the spec's non-goals and must not be attempted as part of this plan:

- Pointing `tictactile.net` at the new app (domains, ACM certificates, DNS)
- Restoring `0-rob-d.mp4` by any means
- Restoring Heroku's automatic GitHub deploys (would require transferring the
  repo to an organization, or MFA access to the `maganeva` account)
- Moving `public/img` to a CDN or object storage
- Deduplicating the two dead `/equiliberrations-2.0` route declarations, or any other change to `app/controllers/index.rb`
