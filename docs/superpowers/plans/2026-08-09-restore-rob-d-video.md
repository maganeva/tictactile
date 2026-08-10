# Restore `0-rob-d.mp4` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/img/videos/0-rob-d.mp4` play and seek in production by committing the 183 MB master as four sub-100 MB chunks and reassembling it into a real file at application boot.

**Architecture:** A stdlib-only `ChunkedAsset` class concatenates ordered chunks from `assets/video-chunks/` into `public/img/videos/0-rob-d.mp4` during `config/environment.rb`. Because `preload_app!` evaluates that file once in the Puma master before forking, the merge happens exactly once per dyno with no locking. Because the assembled file lands in `public/`, Sinatra's existing static handler serves it — `static!` (`sinatra-4.2.1/lib/sinatra/base.rb:1163`) delegates to `send_file` to `Rack::Files#serving` (`rack-3.2.6/lib/rack/files.rb:85-115`), which implements HTTP Range in full. No new route, controller, or view code exists anywhere in this plan.

**Tech Stack:** Ruby 3.4.10, Sinatra 4.2, Puma 8, Minitest + Rack::Test, Rake. Standard library only — `digest`, `json`, `fileutils`, `tmpdir`. **No new gems.**

**Spec:** `docs/superpowers/specs/2026-08-09-rob-d-video-design.md`

## Global Constraints

- **No new gems.** The Gemfile is not modified by this plan.
- **The master is preserved bit-for-bit.** No re-encoding, no transcoding, no lossy step anywhere.
- Master file: `~/dev/tictactile-stashed/0-rob-d.mp4`
- Master size: **191418477** bytes
- Master SHA-256: **f7eb9ccf81da5e7513908c16ee8ed4ed88c1e23ccb532e029c89080e3cae3f22**
- Chunk size: **48 MiB** (`48 * 1024 * 1024` = 50331648 bytes), yielding **4** chunks — three of 50331648 bytes and one of 40423533 bytes. GitHub hard-blocks files at 100 MB and warns at 50 MB; 48 MiB stays under both.
- Chunk glob: **`0-rob-d.mp4.[0-9][0-9][0-9]`** — never `0-rob-d.mp4.*`, which would match the sibling `.manifest` file and concatenate it onto the end of the video.
- Chunks live in `assets/video-chunks/`, **outside `public/`**, or Sinatra would serve the raw chunks to anyone who guessed the URL.
- The assembled file at `public/img/videos/0-rob-d.mp4` is **gitignored** and must never be committed.
- Failure to assemble must **never** prevent the application from booting.
- Existing code style: two-space indent, single-quoted strings unless interpolating, comments that explain *why* (see `test/smoke_test.rb` for the density expected).

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `lib/chunked_asset.rb` | Create | The only new logic. Splits a file into numbered chunks + manifest; reassembles chunks into a target path; verifies by SHA-256. Knows nothing about video, Sinatra, or Heroku. |
| `test/chunked_asset_test.rb` | Create | Unit tests for the above, against byte-sized fixtures in a tmpdir. Runs in milliseconds. |
| `lib/tasks/video.rake` | Create | `video:split` and `video:verify`. Thin wrappers so chunk size and naming live in exactly one place. |
| `Rakefile` | Modify | Load `lib/tasks/*.rake`. |
| `.gitignore` | Modify | Ignore the assembled artifact. |
| `config/environment.rb` | Modify | One lenient call site for `assemble!`. |
| `test/smoke_test.rb` | Modify | Range/206 integration assertions against the real assembled file. |
| `.github/workflows/ci.yml` | Modify | Run `video:verify`; add a Range check to the boot smoke step. |
| `assets/video-chunks/*` | Create (generated) | The four committed chunks + manifest. |
| `README.md` | Modify | Remove the "does not play in production" note. |
| `docs/superpowers/specs/2026-08-08-heroku-deploy-design.md` | Modify | Mark the accepted breakage resolved. |

**Task ordering note:** Task 1 is pure TDD against fixtures and needs no video. Task 2 generates and commits the real chunks. Tasks 3–4 depend on those chunks existing, so they cannot be reordered before Task 2.

---

### Task 1: `ChunkedAsset`

**Files:**
- Create: `lib/chunked_asset.rb`
- Test: `test/chunked_asset_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `ChunkedAsset::Error < StandardError`
  - `ChunkedAsset::CHUNK_SIZE` → `Integer` (50331648)
  - `ChunkedAsset.new(chunk_dir:, basename:, target:)` — all three are `String` or `Pathname`
  - `#assemble!` → `:cached` | `:assembled`, raises `ChunkedAsset::Error`
  - `#verify!` → `:ok`, raises `ChunkedAsset::Error`
  - `#chunk_paths` → `Array<String>`, sorted
  - `#manifest_path` → `String`
  - `ChunkedAsset.split!(source:, chunk_dir:, basename:, chunk_size: CHUNK_SIZE)` → `Integer` (chunk count)

**Why `split!` lives here** and not in the rake task: the chunk naming scheme and manifest format are a single invariant shared by writing and reading. Splitting them across two files is how they drift.

- [ ] **Step 1: Write the failing tests**

Create `test/chunked_asset_test.rb`:

```ruby
ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'tmpdir'
require 'json'
require 'digest'
require_relative '../lib/chunked_asset'

class ChunkedAssetTest < Minitest::Test
  BASENAME = 'sample.bin'

  # Writes a chunk set and manifest into `dir` and returns a ChunkedAsset
  # pointed at it. Manifest values default to the truth about the chunks, so
  # each test overrides only the field it is actually exercising.
  def build(dir, parts, size: nil, sha256: nil, manifest: :default)
    whole = parts.join
    parts.each_with_index do |part, i|
      File.binwrite(File.join(dir, format('%s.%03d', BASENAME, i)), part)
    end

    unless manifest == :omit
      body = if manifest == :default
               JSON.generate(size: size || whole.bytesize,
                             sha256: sha256 || Digest::SHA256.hexdigest(whole))
             else
               manifest
             end
      File.write(File.join(dir, "#{BASENAME}.manifest"), body)
    end

    ChunkedAsset.new(chunk_dir: dir,
                     basename: BASENAME,
                     target: File.join(dir, 'out', BASENAME))
  end

  def test_assembles_chunks_in_order
    Dir.mktmpdir do |dir|
      asset = build(dir, %w[alpha bravo charlie])
      assert_equal :assembled, asset.assemble!
      assert_equal 'alphabravocharlie', File.binread(asset.target)
    end
  end

  # The manifest is a sibling of the chunks. A '.*' glob would match it and
  # sort it after '.002', silently appending JSON to the end of the payload.
  def test_manifest_is_not_concatenated_into_the_output
    Dir.mktmpdir do |dir|
      asset = build(dir, %w[alpha bravo])
      asset.assemble!
      assert_equal 'alphabravo', File.binread(asset.target)
      refute_includes File.binread(asset.target), 'sha256'
    end
  end

  # Lexical sort over zero-padded indices must survive the 9 -> 10 rollover.
  def test_ordering_holds_past_ten_chunks
    Dir.mktmpdir do |dir|
      parts = ('a'..'k').to_a # 11 chunks: .000 through .010
      asset = build(dir, parts)
      asset.assemble!
      assert_equal 'abcdefghijk', File.binread(asset.target)
    end
  end

  def test_skips_when_target_is_already_correct
    Dir.mktmpdir do |dir|
      asset = build(dir, %w[alpha bravo])
      asset.assemble!
      before = File.mtime(asset.target)

      assert_equal :cached, asset.assemble!
      assert_equal before, File.mtime(asset.target)
    end
  end

  def test_remerges_when_target_has_the_wrong_size
    Dir.mktmpdir do |dir|
      asset = build(dir, %w[alpha bravo])
      asset.assemble!
      File.binwrite(asset.target, 'truncated')

      assert_equal :assembled, asset.assemble!
      assert_equal 'alphabravo', File.binread(asset.target)
    end
  end

  def test_raises_when_no_chunks_are_present
    Dir.mktmpdir do |dir|
      asset = build(dir, [])
      error = assert_raises(ChunkedAsset::Error) { asset.assemble! }
      assert_match(/no chunks/, error.message)
    end
  end

  # A gap is caught by its own contiguity check rather than indirectly via the
  # size comparison, so the error names the actual problem.
  def test_raises_when_a_chunk_index_is_missing
    Dir.mktmpdir do |dir|
      asset = build(dir, %w[alpha bravo charlie])
      File.unlink(File.join(dir, format('%s.%03d', BASENAME, 1)))

      error = assert_raises(ChunkedAsset::Error) { asset.assemble! }
      assert_match(/contiguous/, error.message)
    end
  end

  def test_raises_on_size_mismatch_and_leaves_nothing_behind
    Dir.mktmpdir do |dir|
      asset = build(dir, %w[alpha bravo], size: 999)

      error = assert_raises(ChunkedAsset::Error) { asset.assemble! }
      assert_match(/999/, error.message)
      refute File.exist?(asset.target), 'a failed merge must not leave a target'
      refute File.exist?("#{asset.target}.tmp"), 'a failed merge must not leave a .tmp'
    end
  end

  def test_raises_when_the_manifest_is_missing
    Dir.mktmpdir do |dir|
      asset = build(dir, %w[alpha bravo], manifest: :omit)
      error = assert_raises(ChunkedAsset::Error) { asset.assemble! }
      assert_match(/manifest/, error.message)
    end
  end

  def test_raises_when_the_manifest_is_malformed
    Dir.mktmpdir do |dir|
      asset = build(dir, %w[alpha bravo], manifest: 'not json at all')
      error = assert_raises(ChunkedAsset::Error) { asset.assemble! }
      assert_match(/manifest/, error.message)
    end
  end

  # Boot only checks size. verify! is the expensive check that CI runs, so it
  # must catch corruption that preserves length.
  def test_verify_detects_corruption_that_preserves_size
    Dir.mktmpdir do |dir|
      asset = build(dir, %w[alpha bravo], sha256: Digest::SHA256.hexdigest('XXXXXXXXXX'))

      error = assert_raises(ChunkedAsset::Error) { asset.verify! }
      assert_match(/sha256/i, error.message)
    end
  end

  def test_verify_passes_on_an_intact_set
    Dir.mktmpdir do |dir|
      asset = build(dir, %w[alpha bravo])
      assert_equal :ok, asset.verify!
    end
  end

  def test_split_round_trips_through_assemble
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'source.bin')
      payload = Random.new(42).bytes(1000)
      File.binwrite(source, payload)

      count = ChunkedAsset.split!(source: source, chunk_dir: dir,
                                  basename: BASENAME, chunk_size: 300)
      assert_equal 4, count

      asset = ChunkedAsset.new(chunk_dir: dir, basename: BASENAME,
                               target: File.join(dir, 'out', BASENAME))
      assert_equal :ok, asset.verify!
      assert_equal payload, File.binread(asset.target)
    end
  end

  # Re-splitting with a smaller chunk size must not leave higher-numbered
  # chunks from the previous run lying around for the glob to pick up.
  def test_split_clears_stale_chunks_first
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'source.bin')
      File.binwrite(source, 'x' * 1000)

      ChunkedAsset.split!(source: source, chunk_dir: dir, basename: BASENAME, chunk_size: 100)
      ChunkedAsset.split!(source: source, chunk_dir: dir, basename: BASENAME, chunk_size: 500)

      asset = ChunkedAsset.new(chunk_dir: dir, basename: BASENAME,
                               target: File.join(dir, 'out', BASENAME))
      assert_equal 2, asset.chunk_paths.size
      assert_equal :ok, asset.verify!
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bundle exec ruby -Itest test/chunked_asset_test.rb
```

Expected: FAIL — `cannot load such file -- .../lib/chunked_asset`

- [ ] **Step 3: Write the implementation**

Create `lib/chunked_asset.rb`:

```ruby
require 'digest'
require 'fileutils'
require 'json'

# Reassembles a file that was split into numbered chunks so that no single
# piece exceeds GitHub's 100 MB per-file limit.
#
# Deliberately knows nothing about video, Sinatra, or Heroku: it is exercised
# in tests against byte-sized fixtures rather than the 183 MB real payload.
#
# Chunks are named "<basename>.000", "<basename>.001", ... alongside a
# "<basename>.manifest" JSON file recording the original's size and SHA-256.
class ChunkedAsset
  Error = Class.new(StandardError)

  CHUNK_SIZE = 48 * 1024 * 1024 # 48 MiB: under GitHub's 50 MB warning threshold

  # Three explicit digits, never '.*' -- a '.*' glob also matches the sibling
  # '.manifest' file, which sorts after the last chunk and would be silently
  # concatenated onto the end of the payload.
  CHUNK_GLOB_SUFFIX = '.[0-9][0-9][0-9]'.freeze

  attr_reader :chunk_dir, :basename, :target

  def initialize(chunk_dir:, basename:, target:)
    @chunk_dir = chunk_dir.to_s
    @basename  = basename.to_s
    @target    = target.to_s
  end

  # Writes `source` out as chunks plus a manifest, replacing any chunks already
  # present. Returns the number of chunks written.
  def self.split!(source:, chunk_dir:, basename:, chunk_size: CHUNK_SIZE)
    source = source.to_s
    raise Error, "source not found: #{source}" unless File.file?(source)

    FileUtils.mkdir_p(chunk_dir)

    # Clear stale chunks first. A re-split with a larger chunk size produces
    # fewer files, and any leftovers would be picked up by the glob.
    Dir.glob(File.join(chunk_dir, "#{basename}#{CHUNK_GLOB_SUFFIX}")).each { |path| File.unlink(path) }

    count = 0
    File.open(source, 'rb') do |input|
      until input.eof?
        path = File.join(chunk_dir, format('%s.%03d', basename, count))
        File.open(path, 'wb') { |out| IO.copy_stream(input, out, chunk_size) }
        count += 1
      end
    end

    # Digest::SHA256.file streams; it does not read 183 MB into memory.
    File.write(
      File.join(chunk_dir, "#{basename}.manifest"),
      "#{JSON.pretty_generate(size: File.size(source), sha256: Digest::SHA256.file(source).hexdigest)}\n"
    )

    count
  end

  def manifest_path
    File.join(chunk_dir, "#{basename}.manifest")
  end

  def chunk_paths
    Dir.glob(File.join(chunk_dir, "#{basename}#{CHUNK_GLOB_SUFFIX}")).sort
  end

  # Ensures `target` exists and matches the manifest's size.
  # Returns :cached when it was already correct, :assembled when it was written.
  def assemble!
    expected_size = manifest.fetch('size')

    return :cached if File.file?(target) && File.size(target) == expected_size

    paths = chunk_paths
    raise Error, "no chunks matching #{basename}#{CHUNK_GLOB_SUFFIX} in #{chunk_dir}" if paths.empty?

    assert_contiguous!(paths)
    write_atomically(paths, expected_size)

    :assembled
  end

  # The expensive check: full SHA-256 of the assembled file. Runs in CI and
  # from `rake video:verify`, never at boot.
  def verify!
    assemble!

    expected = manifest.fetch('sha256')
    actual   = Digest::SHA256.file(target).hexdigest
    unless actual == expected
      raise Error, "sha256 mismatch for #{target}: got #{actual}, manifest expects #{expected}"
    end

    :ok
  end

  private

  def manifest
    raise Error, "manifest missing at #{manifest_path}" unless File.file?(manifest_path)

    data = JSON.parse(File.read(manifest_path))
    raise Error, "manifest at #{manifest_path} is missing 'size' or 'sha256'" unless
      data.key?('size') && data.key?('sha256')

    data
  rescue JSON::ParserError => e
    raise Error, "manifest at #{manifest_path} is not valid JSON: #{e.message}"
  end

  # A gap in the numbering would otherwise surface only as a confusing size
  # mismatch, so name the real problem.
  def assert_contiguous!(paths)
    indices = paths.map { |path| File.extname(path).delete_prefix('.').to_i }
    return if indices == (0...paths.size).to_a

    raise Error, "chunk indices #{indices.inspect} for #{basename} are not contiguous from 000"
  end

  # Writes to a sibling .tmp and renames. Rename within a filesystem is atomic,
  # so no crash can leave a target that exists but is incomplete.
  def write_atomically(paths, expected_size)
    tmp = "#{target}.tmp"
    FileUtils.mkdir_p(File.dirname(target))

    begin
      File.open(tmp, 'wb') do |out|
        paths.each { |path| File.open(path, 'rb') { |chunk| IO.copy_stream(chunk, out) } }
      end

      actual_size = File.size(tmp)
      unless actual_size == expected_size
        raise Error, "assembled #{actual_size} bytes from #{paths.size} chunk(s), " \
                     "manifest expects #{expected_size}"
      end

      File.rename(tmp, target)
    ensure
      File.unlink(tmp) if File.exist?(tmp)
    end
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bundle exec ruby -Itest test/chunked_asset_test.rb
```

Expected: PASS — 14 runs, 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add lib/chunked_asset.rb test/chunked_asset_test.rb
git commit -m "feat: add ChunkedAsset for splitting and reassembling large files"
```

---

### Task 2: Rake tasks, and generating the real chunks

**Files:**
- Create: `lib/tasks/video.rake`
- Modify: `Rakefile`
- Modify: `.gitignore`
- Create (generated, committed): `assets/video-chunks/0-rob-d.mp4.{000,001,002,003}`, `assets/video-chunks/0-rob-d.mp4.manifest`

**Interfaces:**
- Consumes: `ChunkedAsset.split!`, `#verify!` from Task 1.
- Produces: `rob_d_video` — a method in `lib/tasks/video.rake` returning a configured `ChunkedAsset` for the real video, plus the `APP_ROOT_FROM_TASKS` constant. Task 3 does **not** use either (rake files are not loaded by the app); Task 3 constructs its own instance with the same arguments.

**This task's `.gitignore` step must come before anything that runs `assemble!`.** Once the merged 183 MB file exists in `public/`, an unguarded `git add` would try to commit it.

- [ ] **Step 1: Add the gitignore entry first**

Append to `.gitignore`:

```
# Reassembled at boot from assets/video-chunks/ by ChunkedAsset. 183 MB, and
# larger than GitHub's per-file limit -- it must never be committed.
/public/img/videos/0-rob-d.mp4
```

- [ ] **Step 2: Write the rake tasks**

Create `lib/tasks/video.rake`:

```ruby
require_relative '../chunked_asset'

# NOTE ON THE PATH DEPTH: this file is two directories deep (lib/tasks/), so
# reaching the repo root takes three '..' segments, not the two that
# config/environment.rb uses from one level down. Getting this wrong resolves
# silently to lib/ rather than failing loudly.
APP_ROOT_FROM_TASKS = File.expand_path('../../../', __FILE__)

# The master is intentionally not in the repository: at 183 MB it exceeds
# GitHub's 100 MB per-file limit. It sits beside the repo, not inside it.
# Override with SOURCE= if it lives elsewhere.
DEFAULT_VIDEO_SOURCE = File.expand_path('../tictactile-stashed/0-rob-d.mp4', APP_ROOT_FROM_TASKS)

def rob_d_video
  root = APP_ROOT_FROM_TASKS
  ChunkedAsset.new(
    chunk_dir: File.join(root, 'assets', 'video-chunks'),
    basename: '0-rob-d.mp4',
    target: File.join(root, 'public', 'img', 'videos', '0-rob-d.mp4')
  )
end

namespace :video do
  desc 'Split the 0-rob-d.mp4 master into committable chunks (SOURCE=path to override)'
  task :split do
    source = ENV.fetch('SOURCE', DEFAULT_VIDEO_SOURCE)
    count  = ChunkedAsset.split!(
      source: source,
      chunk_dir: rob_d_video.chunk_dir,
      basename: rob_d_video.basename
    )
    puts "wrote #{count} chunk(s) from #{source}"
    puts File.read(rob_d_video.manifest_path)
  end

  desc 'Assemble 0-rob-d.mp4 from chunks and verify its SHA-256 against the manifest'
  task :verify do
    rob_d_video.verify!
    puts "ok: #{rob_d_video.target} matches the manifest"
  end
end
```

- [ ] **Step 3: Load rake files from the Rakefile**

Modify `Rakefile` — add after the existing `Rake::TestTask` block, before `task default: :test`:

```ruby
Dir.glob('lib/tasks/*.rake').each { |rakefile| load rakefile }
```

- [ ] **Step 4: Generate the chunks**

```bash
bundle exec rake video:split
```

Expected output: `wrote 4 chunk(s) from /home/joe/dev/tictactile-stashed/0-rob-d.mp4`, followed by a manifest showing `"size": 191418477` and `"sha256": "f7eb9ccf81da5e7513908c16ee8ed4ed88c1e23ccb532e029c89080e3cae3f22"`.

- [ ] **Step 5: Confirm the chunk sizes clear GitHub's limit**

```bash
ls -l assets/video-chunks/
```

Expected: four chunks — three at 50331648 bytes and `.003` at 40423533 bytes. **Every one must be under 100000000. Stop and reduce `CHUNK_SIZE` if any is not.**

- [ ] **Step 6: Prove the round trip is byte-identical — this is the gate**

```bash
bundle exec rake video:verify
sha256sum public/img/videos/0-rob-d.mp4
```

Expected: `ok: .../public/img/videos/0-rob-d.mp4 matches the manifest`, and a hash of exactly `f7eb9ccf81da5e7513908c16ee8ed4ed88c1e23ccb532e029c89080e3cae3f22`.

**If the hash differs, stop.** Nothing else in this plan proceeds until the bytes are proven identical to the master.

- [ ] **Step 7: Confirm the assembled file is not stageable**

```bash
git status --porcelain public/img/videos/
```

Expected: **empty output.** If `0-rob-d.mp4` appears, Step 1's gitignore entry is wrong — fix it before continuing.

- [ ] **Step 8: Commit the tooling**

```bash
git add .gitignore Rakefile lib/tasks/video.rake
git commit -m "build: add video:split and video:verify rake tasks"
```

- [ ] **Step 9: Commit the chunks**

This stages ~183 MB across four files; it is slower than a normal commit.

```bash
git add assets/video-chunks/
git status --porcelain assets/video-chunks/   # expect exactly 5 'A' lines
git commit -m "assets: commit 0-rob-d.mp4 as four 48 MiB chunks"
```

---

### Task 3: Assemble at boot, and prove Range works

**Files:**
- Modify: `config/environment.rb`
- Modify: `test/smoke_test.rb`

**Interfaces:**
- Consumes: `ChunkedAsset.new(chunk_dir:, basename:, target:)` and `#assemble!` from Task 1; the committed chunks from Task 2.
- Produces: the file `public/img/videos/0-rob-d.mp4` on disk whenever the app is loaded.

- [ ] **Step 1: Write the failing tests**

Add to `test/smoke_test.rb`, inside `class SmokeTest`, after `test_static_asset_unknown_path_returns_404`:

```ruby
  # 0-rob-d.mp4 is not in the repository as a single file (183 MB exceeds
  # GitHub's per-file limit); config/environment.rb reassembles it from
  # assets/video-chunks/ at load. If that failed, this 404s.
  def test_chunked_video_is_assembled_and_served
    get '/img/videos/0-rob-d.mp4'
    assert_equal 200, last_response.status
    assert_equal '191418477', last_response.headers['content-length']
  end

  # The gallery plays this through a <video> element, and browsers fetch video
  # with Range headers -- Safari refuses a source that answers 200 with a full
  # body, and without Range every seek re-downloads from byte zero. Serving
  # from public/ is what buys this: Sinatra's static! delegates to send_file to
  # Rack::Files, which implements Range. This test is what proves that holds.
  def test_chunked_video_honours_range_requests
    get '/img/videos/0-rob-d.mp4', {}, 'HTTP_RANGE' => 'bytes=0-99'

    assert_equal 206, last_response.status
    assert_equal 'bytes 0-99/191418477', last_response.headers['content-range']
    assert_equal 100, last_response.body.bytesize
  end

  # Chunk .000 ends at byte 50331647, so this range straddles the first chunk
  # boundary. It fails if chunks were concatenated out of order or a boundary
  # was mishandled -- the failure mode a single from-byte-zero test would miss.
  def test_chunked_video_serves_a_range_across_a_chunk_boundary
    get '/img/videos/0-rob-d.mp4', {}, 'HTTP_RANGE' => 'bytes=50331640-50331659'

    assert_equal 206, last_response.status
    assert_equal 'bytes 50331640-50331659/191418477', last_response.headers['content-range']
    assert_equal 20, last_response.body.bytesize
  end

  # Note: no test asserts an `Accept-Ranges` header. Rack::Files does not emit
  # one -- verified against this app by probing an existing static asset. It
  # answers Range requests with 206 regardless, which is what browsers act on.
  #
  # A range starting past the end of the file must be rejected, not clamped.
  def test_chunked_video_rejects_an_unsatisfiable_range
    get '/img/videos/0-rob-d.mp4', {}, 'HTTP_RANGE' => 'bytes=999999999-'
    assert_equal 416, last_response.status
  end

  # The raw chunks live outside public/ precisely so they are not reachable.
  def test_chunks_are_not_served_as_static_assets
    get '/img/videos/0-rob-d.mp4.000'
    assert_equal 404, last_response.status
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

First remove the artifact left by Task 2, so this genuinely tests the boot path:

```bash
rm -f public/img/videos/0-rob-d.mp4
bundle exec ruby -Itest test/smoke_test.rb -n /chunked_video/
```

Expected: FAIL — `Expected: 200, Actual: 404`.

- [ ] **Step 3: Wire the merge into boot**

Modify `config/environment.rb`. Add the require alongside the other requires, after `require 'erb'`:

```ruby
require_relative '../lib/chunked_asset'
```

Then add immediately after the `configure do ... end` block, before the controllers/helpers loading loop:

```ruby
# 0-rob-d.mp4 is 183 MB, over GitHub's 100 MB per-file limit, so it ships as
# chunks under assets/video-chunks/ and is reassembled here. Landing it in
# public/ means Sinatra's ordinary static handler serves it, which is what
# gives us HTTP Range support (via send_file -> Rack::Files) for free.
#
# preload_app! means this runs once in the Puma master before it forks, so
# there is no locking to do and no first visitor waiting on the copy.
#
# Rescued deliberately: a failure here should cost one 404 video tile, which is
# the status quo, not a site that will not boot.
begin
  ChunkedAsset.new(
    chunk_dir: APP_ROOT.join('assets', 'video-chunks'),
    basename: '0-rob-d.mp4',
    target: APP_ROOT.join('public', 'img', 'videos', '0-rob-d.mp4')
  ).assemble!
rescue StandardError => e
  warn "[chunked-asset] 0-rob-d.mp4 unavailable: #{e.class}: #{e.message}"
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
rm -f public/img/videos/0-rob-d.mp4
bundle exec rake test
```

Expected: PASS, all tests, including the five new `chunked_video` / `chunks_are_not_served` tests. Reference values, probed against this app's static handler before this plan was written: a Range request returns `206` with `content-range: bytes 0-99/<size>`, an unsatisfiable range returns `416` with `content-range: bytes */<size>`, and no `accept-ranges` header is sent in either case. The first run reassembles 183 MB, so it takes a second or two longer than usual.

- [ ] **Step 5: Confirm the failure path degrades rather than crashing**

```bash
mv assets/video-chunks/0-rob-d.mp4.manifest /tmp/manifest.bak
rm -f public/img/videos/0-rob-d.mp4
bundle exec ruby -Itest test/smoke_test.rb -n test_get__ 2>&1 | tail -20
mv /tmp/manifest.bak assets/video-chunks/0-rob-d.mp4.manifest
```

Expected: a `[chunked-asset] 0-rob-d.mp4 unavailable: ChunkedAsset::Error: manifest missing at ...` warning on stderr, **and the home-page route test still passing.** The site boots without the video.

- [ ] **Step 6: Verify in a real browser**

```bash
bundle exec puma -C config/puma.rb
```

Open http://localhost:3000, click the "Music Video 2003" thumbnail, confirm it plays, then **drag the scrubber to the middle and confirm it seeks and resumes**. Use Safari if available — it is the client that actually punishes a broken Range implementation. Automated tests prove the bytes are right; only this proves the video is right.

- [ ] **Step 7: Commit**

```bash
git add config/environment.rb test/smoke_test.rb
git commit -m "feat: reassemble 0-rob-d.mp4 from chunks at boot"
```

---

### Task 4: CI coverage

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the `video:verify` task from Task 2; the boot-time assembly from Task 3.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the verify step**

Modify `.github/workflows/ci.yml`. Insert between the `ruby/setup-ruby` step and `- run: bundle exec rake test`:

```yaml
      # The expensive integrity check, kept off the application's boot path so
      # dyno restarts stay well inside Heroku's 60s R10 budget. Running it here
      # means no commit can ship a chunk set that does not reassemble to the
      # original 183 MB master byte for byte.
      - run: bundle exec rake video:verify
```

- [ ] **Step 2: Add the Range smoke check**

In the same file, inside the `Boot the production server` step's `run:` block, add after the existing `asset` curl line and before `kill %1`:

```bash
          code=$(curl -s -r 0-99 -o /dev/null -w '%{http_code}' http://localhost:3000/img/videos/0-rob-d.mp4)
          echo "video range $code"
          [ "$code" = "206" ] || { echo "expected 206 for a Range request, got $code"; exit 1; }
```

The explicit comparison matters: `curl -f` treats `200` as success, so a server that ignored `Range` entirely would pass a naive check while being broken in Safari.

- [ ] **Step 3: Verify the workflow file is valid YAML**

```bash
ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml"); puts "ok"'
```

Expected: `ok`

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: verify the video chunk set and assert 206 on Range requests"
```

- [ ] **Step 5: Push and confirm CI is green**

```bash
git push -u origin restore-rob-d-video
gh run watch
```

Expected: green. This push carries ~183 MB and will be slow.

---

### Task 5: Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-08-heroku-deploy-design.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Fix the README's opening note**

Replace the first line of `README.md`:

```markdown
> **Note**: Portfolio site of the world acclaimed architect and artist 'tictactile'. Images and videos are tracked in this repository, with one exception: `0-rob-d.mp4` exceeds GitHub's 100 MB file limit and therefore does not play in production.
```

with:

```markdown
> **Note**: Portfolio site of the world acclaimed architect and artist 'tictactile'. Images and videos are tracked in this repository. One exception: `0-rob-d.mp4` is 183 MB, over GitHub's 100 MB per-file limit, so it is committed as chunks under `assets/video-chunks/` and reassembled into `public/` at boot. See "large video assets" below.
```

- [ ] **Step 2: Document the workflow in the README**

Add a new section between "adding a gallery item" and "deployment":

```markdown
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
```

- [ ] **Step 3: Mark the accepted breakage resolved**

In `docs/superpowers/specs/2026-08-08-heroku-deploy-design.md`, under "Risks and accepted breakage", replace the paragraph beginning **"The "Music Video 2003" tile will 404."** with:

```markdown
**The "Music Video 2003" tile will 404.** ~~`app/controllers/index.rb:497`
references `/img/videos/0-rob-d.mp4`, which was purged from git history (it
exceeded GitHub's 100 MB file limit) and now exists only as a local copy at
`../tictactile-stashed/`. Since the deploy source is now the GitHub repo, the
file will not be in the slug.~~ **Resolved 2026-08-09** by committing the file
as chunks and reassembling at boot — see
[2026-08-09-rob-d-video-design.md](2026-08-09-rob-d-video-design.md). Note that
this spec expected off-repo hosting to be the fix; it was not. The compressed
slug is comfortably inside Heroku's 1000 MB limit; the binding constraint is
the separate 1 GB uncompressed HEAD-checkout limit, against which this branch
sits at ~381 MB.
```

- [ ] **Step 4: Also correct the stale slug-size figure**

In the same "Risks and accepted breakage" section, the **Slug size** paragraph states "`public/img` is 197 MB, giving a slug around 200 MB". Append to it:

```markdown
Updated 2026-08-09: the committed video chunks add ~183 MB, bringing the
uncompressed HEAD checkout to roughly 381 MB against Heroku's 1 GB
uncompressed-checkout limit — a separate, tighter constraint than the
1000 MB compressed-slug limit this section originally cited as 500 MB. There
is more headroom than originally assumed.
```

- [ ] **Step 5: Commit**

```bash
git add README.md docs/superpowers/specs/2026-08-08-heroku-deploy-design.md
git commit -m "docs: document the chunked video workflow"
git push
```

---

## Deployment (after all tasks, and after the branch is merged)

Not a task — this is the operator procedure, run by a human from a checkout of `main`. Merge the branch first using the project's rebase convention (`git rebase main restore-rob-d-video`, then `git merge --ff-only`).

1. Confirm CI is green on the exact commit being deployed:
   ```bash
   git checkout main && git pull
   gh run list --branch main --limit 1 --json headSha,conclusion,status
   git rev-parse HEAD
   ```
2. `git push heroku main` — **expect a noticeably slower build**, since the slug grows from ~200 MB to ~380 MB and every deploy re-uploads all assets.
3. Watch the boot in `heroku logs --tail`. There should be **no** `[chunked-asset]` warning. Note the time between the dyno starting and the first request served — that is the merge cost, and the number to watch against Heroku's 60-second R10 timeout.
4. Check the dyno's disk headroom, which the spec flags as unmeasured (slug plus the 183 MB assembled copy is ~563 MB):
   ```bash
   heroku ps:exec --dyno=web.1 -- 'df -h /app && du -sh /app/public /app/assets'
   ```
   `heroku run` is the wrong tool here: it starts a separate one-off dyno with its own filesystem, on which the app never booted and the merge never happened, so it would measure the pre-merge slug instead of what the running web dyno actually holds.
5. Verify Range works in production:
   ```bash
   curl -s -r 0-99 -o /dev/null -w '%{http_code}\n' https://tictactile-web-b7da95331725.herokuapp.com/img/videos/0-rob-d.mp4
   ```
   Expected: `206`
6. Load the site, play "Music Video 2003", and seek within it.

**Rollback:** `heroku rollback`. Prior releases exist, and nothing outside `config/environment.rb` changes existing behaviour, so the commit also reverts cleanly.
