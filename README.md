> **Note**: Portfolio site of the world acclaimed architect and artist 'tictactile'. Images and videos are tracked in this repository. One exception: `0-rob-d.mp4` is 183 MB, over GitHub's 100 MB per-file limit, so it is committed as chunks under `assets/video-chunks/` and reassembled into `public/` at boot. See "large video assets" below.

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

### adding a gallery item

Gallery items are Ruby hashes in lists inside `app/controllers/index.rb`
(`@arch`, `@digital`, `@sketches`, `@videos`, `@amphibians`, `@bodyscapes`,
`@metapolis`, etc.), one hash per item, one list per gallery/page.

- `item_anchor` must be unique across **all** lists, not just the one you're
  editing — it becomes the element ID the modal/lightbox looks up, so a
  duplicate anywhere in the file opens the wrong image.
- `thumbnail` and `image` (or, for `@videos`, `video`) are paths under
  `public/` and are case-sensitive. They must match the file on disk exactly,
  including spaces and capitalization (e.g. `/img/Arch/Shell shelter.jpg`).
- `override_thumbnail_class` and `override_image_class` are optional CSS
  classes (e.g. `thumb-wide-left`, `thumb-tall-top`, `img0111`) that control
  how the thumbnail or full image is sized/cropped in the grid; omit them to
  get the default sizing.

### large video assets

`0-rob-d.mp4` is 183 MB, which exceeds GitHub's 100 MB per-file limit. It is
committed as four 48 MiB chunks in `assets/video-chunks/`, plus a manifest
recording the original's size and SHA-256. `config/environment.rb` reassembles
them into `public/img/videos/0-rob-d.mp4` at boot, where Sinatra's ordinary
static handler serves it — which is what gives it HTTP Range support, and so
seeking, for free. The assembled file is gitignored; never commit it.

If the master ever changes, re-chunk it and commit the result:

```bash
bundle exec rake video:split                 # reads ../tictactile-stashed/0-rob-d.mp4
SOURCE=/path/to/new.mp4 bundle exec rake video:split   # or point it elsewhere
bundle exec rake video:verify                # confirms the round trip is byte-identical
git add assets/video-chunks/
```

If assembly fails at boot, the app logs `[chunked-asset] ...` and starts
anyway; that one video 404s and nothing else is affected.

### deployment

One-time setup, on a fresh clone:

```bash
heroku git:remote --app tictactile-web
```

Deploys are manual, from a local checkout of `main`:

```bash
git checkout main && git pull
gh run list --branch main --limit 1 --json headSha,conclusion,status
git rev-parse HEAD   # headSha must match this, and conclusion must be success
git push heroku main
```

GitHub Actions runs the smoke test on every pull request and every push to
`main`, but nothing enforces it at deploy time — checking it is a step in the
procedure. See `docs/superpowers/specs/2026-08-08-heroku-deploy-design.md` for
why Heroku's automatic GitHub deploys are not available for this repository.

