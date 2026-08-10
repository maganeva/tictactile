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
  # Mustermann patterns stringify back to their original route literal. This
  # assumes every route is a literal path (true for all current routes); a
  # future parameterised route (e.g. '/work/:slug') would stringify back to
  # that literal pattern too, producing a test that requests the literal
  # ':slug' path and proves nothing. Revisit this if one is ever added.
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

  # Route tests above only ever exercise app/controllers via Sinatra::Application
  # loaded straight from config/environment.rb — they never parse config.ru, so
  # a broken rackup file (wrong constant, syntax error, etc.) would not fail the
  # suite even though the real server could not boot. Parsing it here closes
  # that hole.
  def test_rackup_file_builds
    app, = Rack::Builder.parse_file('config.ru')
    refute_nil app
  end

  # Every test above is a route test against Sinatra's app object; none of them
  # ever touch the 198 MB of static files in public/. Rack::Test serves static
  # assets through the same app object, so we can confirm public/ is actually
  # there and being served, not just that the routes render.
  def test_static_image_asset_is_served
    get '/img/videos/haiku-th.jpg'
    assert_equal 200, last_response.status
    refute_empty last_response.body
  end

  def test_static_css_asset_is_served
    get '/css/application.css'
    assert_equal 200, last_response.status
    refute_empty last_response.body
  end

  def test_static_js_asset_is_served
    get '/js/application.js'
    assert_equal 200, last_response.status
    refute_empty last_response.body
  end

  def test_static_asset_unknown_path_returns_404
    get '/img/definitely-not-a-real-asset.jpg'
    assert_equal 404, last_response.status
  end

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
    assert_equal 'bytes */191418477', last_response.headers['content-range']
  end
end
