> **Note**: Portfolio site of the world acclaimed architect and artist 'tictactile'. Static resources like videos and images are not uploaded to GitHub.

### [tictactile.com](http://www.tictactile.net)


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

