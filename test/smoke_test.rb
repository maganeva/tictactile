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
