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
