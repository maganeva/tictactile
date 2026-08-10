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
