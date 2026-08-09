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
