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
