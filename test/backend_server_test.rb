require "test_helper"
require "rack/test"
require "backend_server"

ENV['RACK_ENV'] = 'test'

describe WeePrinterBackendServer do
  include Rack::Test::Methods

  def app
    WeePrinterBackendServer
  end

  before do
    Resque.stubs(:enqueue)
  end

  describe "polling printers" do
    describe "with no data" do
      it "returns an empty response" do
        get "/printer/1"
        last_response.body.must_be_empty
      end
    end

    describe "where data exists" do
      it "returns the data as the message body" do
        Printer.stubs(:new).with("1").returns(printer = stub("printer"))
        printer.stubs(:archive_and_return_print_data).returns("data")
        get "/printer/1"
        last_response.body.must_be :==, "data"
      end
    end
  end

  describe "print submissions" do
    it "enqueues the url with the printer id" do
      Resque.expects(:enqueue).with(Jobs::PreparePage, "1", "submitted-url")
      get "/print/1?url=submitted-url"
    end

    it "determines the URL from the HTTP_REFERER if no url parameter exists" do
      Resque.expects(:enqueue).with(Jobs::PreparePage, "1", "referer-url")
      get "/print/1", {}, {"HTTP_REFERER" => "referer-url"}
    end

    it "prefers the url parameter to the HTTP_REFERER" do
      Resque.expects(:enqueue).with(Jobs::PreparePage, "1", "param-url")
      get "/print/1?url=param-url", {}, {"HTTP_REFERER" => "referer-url"}
    end

    it "shows a success page" do
      get "/print/1", {}, {"HTTP_REFERER" => "http://referer-url"}
      last_response.ok?.must_be :==, true
    end

    it "also accepts POSTed data" do
      post "/print/1", {url: "http://param-url"}, {"HTTP_REFERER" => "http://referer-url"}
      last_response.ok?.must_be :==, true
    end
  end

  describe "previewing" do
    it "enqueues a job to generate a preview" do
      Resque.expects(:enqueue).with(Jobs::Preview, random_id = regexp_matches(/[a-f0-9]{16}/), "submitted-url")
      get "/preview?url=submitted-url"
    end

    it "determines the URL from the HTTP_REFERER if no url parameter exists" do
      Resque.expects(:enqueue).with(Jobs::Preview, random_id = regexp_matches(/[a-f0-9]{16}/), "referer-url")
      get "/preview", {}, {"HTTP_REFERER" => "referer-url"}
    end

    it "redirects to a holding page after requesting" do
      get "/preview?url=submitted-url"
      last_response.redirect?.must_be :==, true
      last_response.location.must_match /#{Regexp.escape("http://example.org/preview/pending/")}[a-f0-9]{16}/
    end

    it "redirects to the preview page once the preview data exists" do
      Preview.stubs(:find).with("abc123def456abcd").returns("data")
      get "/preview/pending/abc123def456abcd"
      last_response.redirect?.must_be :==, true
      last_response.location.must_match /#{Regexp.escape("http://example.org/preview/show/")}[a-f0-9]{16}/
    end

    it "allows posting of a URL for preview" do
      post "/preview", {url: "submitted-url"}
      last_response.redirect?.must_be :==, true
      last_response.location.must_match /#{Regexp.escape("http://example.org/preview/pending/")}[a-f0-9]{16}/
    end
  end
end