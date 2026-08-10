# Set up gems listed in the Gemfile.
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../Gemfile', __FILE__)

require 'bundler/setup' if File.exist?(ENV['BUNDLE_GEMFILE'])

require 'pathname'

require 'sinatra'
require 'sinatra/reloader' if development?

require 'erb'

require_relative '../lib/chunked_asset'

# Some helper constants for path-centric logic
APP_ROOT = Pathname.new(File.expand_path('../../', __FILE__))

configure do
  # By default, Sinatra assumes that the root is the file that calls the
  # configure block. Since this is not the case for us, we set it manually.
  set :root, APP_ROOT.to_path

  # Set the views to app/views
  set :views, File.join(Sinatra::Application.root, 'app', 'views')

  # Without this, static responses carry Last-Modified but no Cache-Control,
  # so every repeat view of the ~87 assets the home page references costs a
  # revalidation round-trip against the (small) Puma thread pool.
  set :static_cache_control, [:public, max_age: 86_400]
end

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

# Set up the controllers and helpers
Dir[APP_ROOT.join('app', 'controllers', '*.rb')].each { |file| require file }
Dir[APP_ROOT.join('app', 'helpers', '*.rb')].each { |file| require file }
