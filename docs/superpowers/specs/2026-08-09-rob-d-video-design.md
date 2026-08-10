# Restoring `0-rob-d.mp4` by committing it as chunks and reassembling at boot

**Date:** 2026-08-09
**Status:** Approved, ready for implementation planning

## Context

`app/controllers/index.rb:497` declares the "Music Video 2003" gallery item with
`video: '/img/videos/0-rob-d.mp4'`. That file is 191,418,477 bytes (183 MB),
which exceeds GitHub's hard 100 MB per-file limit, so it was purged from git
history during the Heroku migration and now exists only as a local copy at
`~/dev/tictactile-stashed/0-rob-d.mp4`. Since the deploy source is a GitHub
checkout, the file is absent from the slug and the URL 404s in production.

The [Heroku deploy spec](2026-08-08-heroku-deploy-design.md) recorded this as
deliberate accepted breakage, and named off-repo hosting as the eventual fix.
This spec supersedes that expectation: the file will be restored **in-repo**,
split into chunks that clear the per-file limit and reassembled into a real file
on disk at application boot.

Two findings from investigation shape the whole design.

**Range requests are the binding constraint.** The player is a `<video controls>`
element whose `src` is assigned lazily on thumbnail click
(`public/js/application.js:181`). Browsers fetch video with `Range:` headers;
Safari and iOS in practice refuse a source that answers `200` with a full body,
and without Range every seek re-downloads from byte zero. Any solution must
speak `206`, `Content-Range`, `416`, `If-Range`, and `HEAD` correctly.

**That protocol work is already done, and reachable for free.** Sinatra's static
handler (`sinatra-4.2.1/lib/sinatra/base.rb:1163`, `static!`) ends in
`send_file`, which delegates to `Rack::Files#serving`
(`rack-3.2.6/lib/rack/files.rb:85-115`) — a complete Range implementation
including multipart byteranges and `416` with `Content-Range: bytes */size`.
Therefore: **if the assembled file simply exists at
`public/img/videos/0-rob-d.mp4`, the existing static path serves it correctly
with no new route, controller, or view code.**

A measured `IO.copy_stream` of the full 183 MB completed in 0.48s locally,
against Heroku's 60-second R10 boot budget.

## Goals

1. `/img/videos/0-rob-d.mp4` returns `206 Partial Content` for Range requests in
   production, and the video plays and seeks in a browser.
2. The bytes served are identical to the master, verified by SHA-256.
3. Nothing in the repository exceeds GitHub's 100 MB per-file limit.
4. A failure to assemble degrades to today's behaviour (one 404 tile), never to
   a site that will not boot.

## Non-goals

- Re-encoding the video. Considered and rejected: the master is to be preserved
  bit-for-bit.
- Off-repo hosting (S3, Cloudflare R2, Git LFS, GitHub Release assets).
  Considered and rejected in favour of staying self-contained.
- Changing how any other asset is stored or served.
- Solving Puma thread occupancy for large media. See "Risks" below.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Storage | Chunks committed to the repo | Preserves the master bit-for-bit and keeps the project self-contained, with no external account, credential, or URL that can rot. |
| Assembly target | `public/img/videos/0-rob-d.mp4` | Puts the file where Sinatra's existing static handler already looks, so Range support comes from `Rack::Files` and no application code serves video. |
| Assembly timing | At boot, in `config/environment.rb` | `preload_app!` (`config/puma.rb`) evaluates it once in the Puma master before forking, so there is no lock to write, no thundering herd across the 10 request slots, and no first visitor waiting on a 183 MB copy. |
| Streaming chunks per request | Rejected | Would require hand-implementing Range, `Content-Range`, `416`, `If-Range`, and `HEAD` over a chunk sequence — reimplementing `Rack::Files` and owning it forever, to serve one file. |
| Chunk size | 48 MiB, four chunks | GitHub hard-blocks at 100 MB and warns at 50 MB; 48 MiB keeps pushes silent with headroom. Two chunks of ~91 MB would clear the limit but sit uncomfortably close to it. |
| Chunk location | `assets/video-chunks/`, outside `public/` | Under `public/`, Sinatra would serve the raw chunks to anyone who guessed the URL. |
| Boot-time verification | Size only | Cheap, and catches truncation. Git content-addresses and verifies blobs on checkout, so a right-sized-but-corrupt chunk is not a realistic failure mode; paying ~0.5s of hashing on every dyno restart to defend against it is a poor trade against R10. |
| Full SHA-256 verification | `rake video:verify`, run in CI | Keeps the expensive check off the boot path while still gating every commit. |
| Failure policy | Class raises; boot site rescues and warns | Tests and rake tasks get precise assertable exceptions; production gets a site that boots. A broken manifest costs one 404 tile, visibly logged. |

## Layout

```
assets/video-chunks/0-rob-d.mp4.000     48 MiB
assets/video-chunks/0-rob-d.mp4.001     48 MiB
assets/video-chunks/0-rob-d.mp4.002     48 MiB
assets/video-chunks/0-rob-d.mp4.003     38.55 MiB (40,423,533 bytes)
assets/video-chunks/0-rob-d.mp4.manifest    total byte size + SHA-256 of the master
```

Zero-padded numeric suffixes, so a plain lexical sort is the correct order — no
parsing and no off-by-one.

The chunk glob must be `0-rob-d.mp4.[0-9][0-9][0-9]`, **not** `0-rob-d.mp4.*`.
The looser pattern would sweep the manifest into the chunk list and concatenate
it onto the end of the video.

## Data flow

```
repo:    assets/video-chunks/0-rob-d.mp4.000 … .003   (committed)
              |
              |  boot-time merge, once per dyno, via config/environment.rb
              v
dyno fs: public/img/videos/0-rob-d.mp4               (gitignored, ephemeral)
              |
              |  Sinatra static! -> send_file -> Rack::Files
              v
browser: GET /img/videos/0-rob-d.mp4  Range: bytes=0-   ->  206 Partial Content
```

## Components

### `lib/chunked_asset.rb`

One class with one job: *given an ordered set of chunks and a target path,
ensure the target exists and is complete.* It knows nothing about video,
Sinatra, or Heroku, which is what makes it testable against 100-byte fixtures
instead of a 183 MB one.

```ruby
ChunkedAsset.new(
  chunks: APP_ROOT.join('assets', 'video-chunks', '0-rob-d.mp4.[0-9][0-9][0-9]'),
  target: APP_ROOT.join('public', 'img', 'videos', '0-rob-d.mp4'),
).assemble!
```

`assemble!`:

1. If the target exists and its size matches the manifest, return without doing
   work. On Heroku this is never true — the filesystem is fresh every boot. In
   local development it means the merge happens once and never again.
2. Otherwise `IO.copy_stream` each chunk in lexical order into a `.tmp` sibling.
3. Compare the assembled size against the manifest.
4. `File.rename` into place. Rename within a filesystem is atomic, so no crash
   can leave a partial file that looks valid.

An `ensure` block unlinks the `.tmp` on any failure. Every anomaly — missing
chunk, missing or malformed manifest, size mismatch, `ENOSPC` — raises.

### `config/environment.rb`

A single lenient call site, so the file stays declarative:

```ruby
begin
  ChunkedAsset.new(...).assemble!
rescue => e
  warn "[chunked-asset] 0-rob-d.mp4 unavailable: #{e.message}"
end
```

### Rake tasks

- `video:split` — regenerates chunks and manifest from
  `~/dev/tictactile-stashed/0-rob-d.mp4`. A task rather than a documented shell
  incantation, so chunk size and naming live in exactly one place.
- `video:verify` — assembles and SHA-256s against the manifest. Runs in CI.

### `.gitignore`

```
/public/img/videos/0-rob-d.mp4
```

Without this, the merged 183 MB artifact eventually gets committed and recreates
the original problem. GitHub's 100 MB limit is a natural backstop, but relying on
a push failure as a safety net is unpleasant.

## Concurrency

`preload_app!` means `config/environment.rb` is evaluated once in the Puma
master before it forks its two workers, so exactly one process ever merges.
Because step 1 short-circuits on an already-correct target, re-running is a
no-op, which also covers `sinatra/reloader` re-evaluation in development.

## Testing

**Unit tests** against tiny fixtures in a `Dir.mktmpdir`:

- chunks assemble in order, byte-identical to the expected whole
- existing target of the right size is skipped, not rewritten
- existing target of the wrong size is re-merged
- missing chunk raises; target absent; no `.tmp` left behind
- size mismatch raises; target absent; no `.tmp` left behind
- ordering holds past ten chunks (`.009` sorts before `.010`)
- a sibling `.manifest` file in the chunk directory is not concatenated into the
  output

**Integration test** in the existing minitest + rack-test suite, asserting the
behaviour that actually matters:

```
GET /img/videos/0-rob-d.mp4  Range: bytes=0-99
  -> 206, Content-Range: bytes 0-99/191418477, body 100 bytes
GET /img/videos/0-rob-d.mp4  Range: bytes=50331640-50331659   (spans a chunk boundary)
  -> 206, Content-Range: bytes 50331640-50331659/191418477, body 20 bytes
GET /img/videos/0-rob-d.mp4  Range: bytes=999999999-
  -> 416, Content-Range: bytes */191418477
GET /img/videos/0-rob-d.mp4
  -> 200, Content-Length: 191418477
```

Note: `Rack::Files` does **not** emit an `Accept-Ranges` header — verified by
probing this app's static handler against an existing asset. It answers Range
requests with `206` regardless, which is what browsers act on, so no test
asserts that header.

This runs against the genuinely assembled file, since `environment.rb` has
already merged it by the time the suite loads, so it exercises the real boot
path rather than a mock of it.

**CI** gains `rake video:verify`, and the existing "Boot the production server"
step gains a Range check alongside its current asset check. CI checkouts pull
183 MB more and each run performs the merge; the cost is seconds.

**Manual, before deploying:** play the video in a browser and seek within it,
ideally in Safari — the client that actually punishes a broken Range
implementation. The automated tests prove the bytes are right; only this proves
the video is right.

## Risks and accepted costs

**Slug size.** ~200 MB to ~380 MB of largely incompressible media against
Heroku's 500 MB limit. The Heroku deploy spec already named slug size as the cap
on committing more media; this spends most of what remained. The next large
asset will force the off-repo conversation this spec defers.

**Repository size.** `.git` grows from 377 MB to roughly 560 MB. Every future
clone and CI checkout pays it.

**One video download occupies one of ten request slots for its full duration.**
`threads 5,5` across two workers, and Heroku's router streams response bodies
rather than buffering them. This design does not introduce the problem —
`haiku.mp4` at 57 MB already has it — but it commits to serving 183 MB from the
dyno, which is roughly 3x worse per viewer. At portfolio traffic this is
theoretical. It is also precisely what off-repo hosting would have solved, and
is recorded here so the trade is a decision rather than an oversight.

**Every dyno restart re-merges.** Heroku cycles dynos at least daily. Measured
sub-second locally, likely a few seconds on Heroku, against a 60-second R10
budget. Comfortable, but it is a new boot-time cost and is the number to watch
in the logs on first deploy.

**Ephemeral disk at ~563 MB is unmeasured on Heroku** (slug plus merged copy).
Expected to be fine, and to be confirmed from `heroku logs` rather than designed
around speculatively. Escape hatch if it is not: unlink the chunks after a
successful merge, since the slug is extracted onto writable disk. Deliberately
not done up front — it guards an unmeasured problem and makes re-merging
impossible.

**Re-chunking is a manual discipline.** If the master ever changes, someone must
re-run `video:split` and commit new chunks. The manifest turns "forgot to" into
a loud boot-time error rather than a silently stale video.

**Incidental benefit:** the master currently exists as a single un-backed-up
local copy. Afterwards the repository holds a bit-for-bit reconstructable copy.

## Rollout

1. Branch off `main`.
2. `lib/chunked_asset.rb` and its unit tests, test-first.
3. `video:split` and `video:verify` rake tasks.
4. Run `video:split`; confirm the reassembled file's SHA-256 matches
   `~/dev/tictactile-stashed/0-rob-d.mp4` exactly. **This is the gate** —
   nothing proceeds until the bytes are proven identical.
5. Add the `.gitignore` entry.
6. Wire the lenient call into `config/environment.rb`.
7. Integration test, then a real browser play-and-seek locally.
8. Commit the four chunks and push. One ~183 MB push, well inside GitHub's
   limits, but slow.
9. Confirm CI green, now including `video:verify` and the Range check.
10. Deploy per the README procedure. Expect a noticeably slower build — 380 MB
    of slug uploading from a local checkout — and watch the logs for the merge
    line.
11. Verify live: `curl -r 0-99 -o /dev/null -w '%{http_code}'` returns `206`,
    then play and seek in a browser.
12. Update the README's opening note, which currently states the video does not
    play in production, and the Heroku deploy spec's accepted-breakage entry.

**Rollback** is cheap: prior releases exist so `heroku rollback` works, and the
commit reverts cleanly, since nothing outside `config/environment.rb` changes
existing behaviour.
