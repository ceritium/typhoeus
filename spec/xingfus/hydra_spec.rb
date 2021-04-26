require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

# some of these tests assume that you have some local services running.
# ruby spec/servers/app.rb -p 3000
# ruby spec/servers/app.rb -p 3001
# ruby spec/servers/app.rb -p 3002
describe Xingfus::Hydra do
  before(:all) do
    cache_class = Class.new do
      def initialize
        @cache = {}
      end
      def get(key)
        @cache[key]
      end
      def set(key, object, timeout = 0)
        @cache[key] = object
      end
    end
    @cache = cache_class.new
  end

  it "has a singleton" do
    Xingfus::Hydra.hydra.should be_a Xingfus::Hydra
  end

  it "has a setter for the singleton" do
    Xingfus::Hydra.hydra = :foo
    Xingfus::Hydra.hydra.should == :foo
    Xingfus::Hydra.hydra = Xingfus::Hydra.new
  end

  it "queues a request" do
    hydra = Xingfus::Hydra.new
    hydra.queue Xingfus::Request.new("http://localhost:3000")
  end

  it "runs a batch of requests" do
    hydra  = Xingfus::Hydra.new
    first  = Xingfus::Request.new("http://localhost:3000/first")
    second = Xingfus::Request.new("http://localhost:3001/second")
    hydra.queue first
    hydra.queue second
    hydra.run
    first.response.body.should include("first")
    first.performed?.should be_true
    second.response.body.should include("second")
    second.performed?.should be_true
  end

  it "runs queued requests in order of queuing" do
    hydra  = Xingfus::Hydra.new :max_concurrency => 1
    first  = Xingfus::Request.new("http://localhost:3000/first")
    second = Xingfus::Request.new("http://localhost:3001/second")
    third = Xingfus::Request.new("http://localhost:3001/third")
    second.on_complete do |response|
      first.response.should_not == nil
      third.response.should == nil
    end
    third.on_complete do |response|
      first.response.should_not == nil
      second.response.should_not == nil
    end

    hydra.queue first
    hydra.queue second
    hydra.queue third
    hydra.run
    first.response.body.should include("first")
    second.response.body.should include("second")
    third.response.body.should include("third")
    first.performed?.should be_true
    second.performed?.should be_true
    third.performed?.should be_true
  end

  it "aborts all other and queued requests if an exception raises in a callback" do
    invoked_callbacks = 0

    hydra  = Xingfus::Hydra.new(:max_concurrency => 1)
    first  = Xingfus::Request.new("http://localhost:3000/first")
    second = Xingfus::Request.new("http://localhost:3001/second")
    third  = Xingfus::Request.new("http://localhost:3001/third")

    first.on_complete do
      invoked_callbacks += 1
      raise "foobar"
    end
    second.on_complete { invoked_callbacks += 1 }
    third.on_complete  { invoked_callbacks += 1 }
    [first, second, third].each {|request| hydra.queue request }

    expect { hydra.run }.to raise_error(RuntimeError)

    # at this time the second request is already marked as performed
    third.performed?.should be_false
    invoked_callbacks.should == 1
    hydra.instance_variable_get("@queued_requests").should == []
  end

  it "should store the curl return codes on the reponses" do
    hydra  = Xingfus::Hydra.new
    first  = Xingfus::Request.new("http://localhost:3001/?delay=1", :timeout => 100)
    second = Xingfus::Request.new("http://localhost:3999", :connect_timout => 100)
    hydra.queue first
    hydra.queue second
    hydra.run
    first.response.curl_return_code == 28
    second.response.curl_return_code == 7
  end

  it "aborts a batch of requests" do
    urls = [
        'http://localhost:3000',
        'http://localhost:3001',
        'http://localhost:3002'
    ]

    # this will make testing easier
    hydra     = Xingfus::Hydra.new(:max_concurrency => 1 )
    completed = 0

    10.times {
        |i|

        req = Xingfus::Request.new(urls[i % urls.size], :params => { :cnt => i } )
        req.on_complete {
            |res|
            completed += 1
            hydra.abort if completed == 5
        }

        hydra.queue( req )
    }

    hydra.run

    # technically this should be '== 6' but I don't trust it...
    completed.should < 10
  end

  it "abort! resets easy handles and caches" do
    hydra  = Xingfus::Hydra.new(:max_concurrency => 1)
    2.times do
      hydra.queue Xingfus::Request.new("http://localhost:3000/foo")
    end

    hydra.instance_variable_get("@queued_requests").size.should == 1
    hydra.instance_variable_get("@memoized_requests").size.should == 1
    hydra.instance_variable_get("@running_requests").should == 1
    hydra.instance_variable_get("@multi").easy_handles.size == 1

    hydra.abort!

    hydra.instance_variable_get("@queued_requests").size.should == 0
    hydra.instance_variable_get("@memoized_requests").size.should == 0
    hydra.instance_variable_get("@running_requests").should == 0
    hydra.instance_variable_get("@multi").easy_handles.size == 0
  end

  it "has a cache_setter proc" do
    hydra = Xingfus::Hydra.new
    hydra.cache_setter do |request|
      # @cache.set(request.cache_key, request.response, request.cache_timeout)
    end
  end

  it "has a cache_getter" do
    hydra = Xingfus::Hydra.new
    hydra.cache_getter do |request|
      # @cache.get(request.cache_key) rescue nil
    end
  end

  it "memoizes GET reqeusts" do
    hydra  = Xingfus::Hydra.new
    first  = Xingfus::Request.new("http://localhost:3000/foo", :params => { :delay => 1})
    second = Xingfus::Request.new("http://localhost:3000/foo", :params => { :delay => 1})
    hydra.queue first
    hydra.queue second
    start_time = Time.now
    hydra.run
    first.response.body.should include("foo")
    first.handled_response.body.should include("foo")
    first.response.should == second.response
    first.handled_response.should == second.handled_response
    (Time.now - start_time).should < 1.2 # if it had run twice it would be ~ 2 seconds
    first.performed?.should == !second.performed?
  end

  it "runs the handlers for all requests, queued before running the queue" do
    hydra  = Xingfus::Hydra.new
    first  = Xingfus::Request.new("http://localhost:3000/foo", :params => { :delay => 0})
    second = Xingfus::Request.new("http://localhost:3000/foo", :params => { :delay => 0})
    call_count = 0
    first.on_complete { |response| call_count += 1 }
    second.on_complete { |response| call_count += 1 }
    hydra.queue first
    hydra.queue second
    hydra.run
    call_count.should == 2
    first.performed?.should == !second.performed?
  end

  it "runs the handlers for all requests, even if queued in a callback" do
    hydra  = Xingfus::Hydra.new
    first  = Xingfus::Request.new("http://localhost:3000/foo", :params => { :delay => 0})
    second = Xingfus::Request.new("http://localhost:3000/foo", :params => { :delay => 0})
    call_count = 0
    first.on_complete { |response| call_count += 1; hydra.queue second }
    second.on_complete { |response| call_count += 1 }
    hydra.queue first
    hydra.run
    call_count.should == 2
    first.performed?.should == !second.performed?
  end

  it "runs the handlers for all requests, even if queued in a callback in strange order" do
    hydra  = Xingfus::Hydra.new
    first  = Xingfus::Request.new("http://localhost:3000/foo", :params => { :delay => 1})
    second = Xingfus::Request.new("http://localhost:3000/bar", :params => { :delay => 2})
    third  = Xingfus::Request.new("http://localhost:3000/baz", :params => { :delay => 0})
    fourth = Xingfus::Request.new("http://localhost:3000/baz", :params => { :delay => 0})

    call_count = 0
    first.on_complete { |response| call_count += 1; hydra.queue third }
    second.on_complete { |response| call_count += 1 ; hydra.queue fourth}
    third.on_complete { |response| call_count += 1}
    fourth.on_complete { |response| call_count += 1 }

    hydra.queue first
    hydra.queue second
    hydra.run
    call_count.should == 4
    first.performed?.should be_true
    second.performed?.should be_true
    third.performed?.should == !fourth.performed?
  end

  it "continues queued requests after a memoization hit" do
    # Set max_concurrency to 1 so that the second and third requests will end
    # up in the request queue.
    hydra  = Xingfus::Hydra.new :max_concurrency => 1

    first  = Xingfus::Request.new("http://localhost:3000/foo", :params => { :delay => 1})
    second = Xingfus::Request.new("http://localhost:3000/foo", :params => { :delay => 1})
    third = Xingfus::Request.new("http://localhost:3000/bar", :params => { :delay => 1})
    hydra.queue first
    hydra.queue second
    hydra.queue third
    hydra.run

    first.response.body.should include("foo")
    second.response.body.should include("foo")
    third.response.body.should include("bar")
    first.performed?.should == !second.performed?
    third.performed?.should be_true
  end

  it "can turn off memoization for GET requests" do
    hydra  = Xingfus::Hydra.new
    hydra.disable_memoization
    first  = Xingfus::Request.new("http://localhost:3000/foo")
    second = Xingfus::Request.new("http://localhost:3000/foo")
    hydra.queue first
    hydra.queue second
    hydra.run
    first.response.body.should include("foo")
    first.response.object_id.should_not == second.response.object_id
    first.performed?.should be_true
    second.performed?.should be_true
  end

  it "pulls GETs from cache" do
    hydra  = Xingfus::Hydra.new
    start_time = Time.now
    hydra.cache_getter do |request|
      @cache.get(request.cache_key) rescue nil
    end
    hydra.cache_setter do |request|
      @cache.set(request.cache_key, request.response, request.cache_timeout)
    end

    first  = Xingfus::Request.new("http://localhost:3000/foo", :params => { :delay => 1})
    cached_response = double("foo", :code => 200, :curl_return_code => 0)
    @cache.set(first.cache_key, cached_response, 60)
    hydra.queue first
    hydra.run
    (Time.now - start_time).should < 0.1
    first.response.should == cached_response
    first.performed?.should be_false
  end

  it "sets GET responses to cache when the request has a cache_timeout value" do
    hydra  = Xingfus::Hydra.new
    hydra.cache_getter do |request|
      @cache.get(request.cache_key) rescue nil
    end
    hydra.cache_setter do |request|
      @cache.set(request.cache_key, request.response, request.cache_timeout)
    end

    first  = Xingfus::Request.new("http://localhost:3000/first", :cache_timeout => 0)
    second = Xingfus::Request.new("http://localhost:3000/second")
    hydra.queue first
    hydra.queue second
    hydra.run
    first.response.body.should include("first")
    @cache.get(first.cache_key).should == first.response
    @cache.get(second.cache_key).should be_nil
  end

  it "continues queued requests after a queued cache hit" do
    # Set max_concurrency to 1 so that the second and third requests will end
    # up in the request queue.
    hydra  = Xingfus::Hydra.new :max_concurrency => 1
    hydra.cache_getter do |request|
      @cache.get(request.cache_key) rescue nil
    end
    hydra.cache_setter do |request|
      @cache.set(request.cache_key, request.response, request.cache_timeout)
    end

    first  = Xingfus::Request.new("http://localhost:3000/first", :params => { :delay => 1})
    second = Xingfus::Request.new("http://localhost:3000/second", :params => { :delay => 1})
    third = Xingfus::Request.new("http://localhost:3000/third", :params => { :delay => 1})
    second_response = double("second", :code => 200, :curl_return_code => 0)
    @cache.set(second.cache_key, second_response, 60)
    hydra.queue first
    hydra.queue second
    hydra.queue third
    hydra.run

    first.response.body.should include("first")
    second.response.should == second_response
    third.response.body.should include("third")
  end

  it "has a global on_complete" do
    foo = nil
    hydra  = Xingfus::Hydra.new
    hydra.on_complete do |response|
      foo = :called
    end

    first  = Xingfus::Request.new("http://localhost:3000/first")
    hydra.queue first
    hydra.run
    first.response.body.should include("first")
    foo.should == :called
  end

  it "has a global on_complete setter" do
    foo = nil
    hydra  = Xingfus::Hydra.new
    proc = Proc.new {|response| foo = :called}
    hydra.on_complete = proc

    first  = Xingfus::Request.new("http://localhost:3000/first")
    hydra.queue first
    hydra.run
    first.response.body.should include("first")
    foo.should == :called
  end

  it "should reuse connections from the pool for a host"

  it "should queue up requests while others are running" do
    hydra   = Xingfus::Hydra.new

    start_time = Time.now
    @responses = []

    request = Xingfus::Request.new("http://localhost:3000/first", :params => { :delay => 1})
    request.on_complete do |response|
      @responses << response
      response.body.should include("first")
    end

    request.after_complete do |object|
      second_request = Xingfus::Request.new("http://localhost:3001/second", :params => { :delay => 2})
      second_request.on_complete do |response|
        @responses << response
        response.body.should include("second")
      end
      hydra.queue second_request
    end
    hydra.queue request

    third_request = Xingfus::Request.new("http://localhost:3002/third", :params => { :delay => 3})
    third_request.on_complete do |response|
      @responses << response
      response.body.should include("third")
    end
    hydra.queue third_request

    hydra.run
    @responses.size.should == 3
    (Time.now - start_time).should < 3.3
  end

  it "should fire and forget" do
    # this test is totally hacky. I have no clue how to make it verify. I just look at the test servers
    # to verify that stuff is running
    hydra  = Xingfus::Hydra.new
    first  = Xingfus::Request.new("http://localhost:3000/first?delay=1")
    second = Xingfus::Request.new("http://localhost:3001/second?delay=2")
    hydra.queue first
    hydra.queue second
    hydra.fire_and_forget
    third = Xingfus::Request.new("http://localhost:3002/third?delay=3")
    hydra.queue third
    hydra.fire_and_forget
    sleep 3 # have to do this or future tests may break.
  end

  it "should take the maximum number of concurrent requests as an argument" do
    hydra = Xingfus::Hydra.new(:max_concurrency => 2)
    first  = Xingfus::Request.new("http://localhost:3000/first?delay=1")
    second = Xingfus::Request.new("http://localhost:3001/second?delay=1")
    third  = Xingfus::Request.new("http://localhost:3002/third?delay=1")
    hydra.queue first
    hydra.queue second
    hydra.queue third

    start_time = Time.now
    hydra.run
    finish_time = Time.now

    first.response.code.should == 200
    second.response.code.should == 200
    third.response.code.should == 200
    (finish_time - start_time).should > 2.0
  end

  it "should respect the follow_location option when set on a request" do
    hydra = Xingfus::Hydra.new
    request = Xingfus::Request.new("http://localhost:3000/redirect", :follow_location => true)
    hydra.queue request
    hydra.run

    request.response.code.should == 200
  end

  it "should pass through the max_redirects option when set on a request" do
    hydra = Xingfus::Hydra.new
    request = Xingfus::Request.new("http://localhost:3000/bad_redirect", :max_redirects => 5)
    hydra.queue request
    hydra.run

    request.response.code.should == 302
  end

  describe "retry_request?" do
    let(:hydra)    { Xingfus::Hydra.new }
    let(:request)  { Xingfus::Request.new("/foo", :method => method) }
    let(:response) { Xingfus::Response.new }

    context "for non-GET request" do
      let(:method) { :put }

      context "when retry_connect_timeouts is disabled" do
        it "returns false on connect timeout" do
          response.stub(:connect_timed_out?).and_return(true)
          hydra.retry_request?(request, response).should be_false
        end
      end

      context "when retry_connect_timeouts is enabled" do
        before do
          hydra.retry_connect_timeouts = true
        end

        it "returns true on connect timeout" do
          response.stub(:connect_timed_out?).and_return(true)
          hydra.retry_request?(request, response).should be_true
        end
      end
    end

    context "for GET request" do
      let(:method) { :get }

      context "when retry_connect_timeouts is disabled" do
        it "returns false on connect timeout" do
          response.stub(:connect_timed_out?).and_return(true)
          hydra.retry_request?(request, response).should be_false
        end
      end

      context "when retry_connect_timeouts is enabled" do
        before do
          hydra.retry_connect_timeouts = true
        end

        it "returns true on connect timeout" do
          response.stub(:connect_timed_out?).and_return(true)
          hydra.retry_request?(request, response).should be_true
        end

        it "returns false on normal timeout" do
          response.stub(:connect_timed_out?).and_return(false)
          hydra.retry_request?(request, response).should be_false
        end
      end

      context "when curl_retry_codes is [56]" do
        before do
          hydra.curl_retry_codes = [56]
        end

        it "should retry when curl_return_code is 56" do
          response.stub(:curl_return_code).and_return(56)
          hydra.retry_request?(request, response).should be_true
        end

        it "should not retry when curl_return_code is 57" do
          response.stub(:curl_return_code).and_return(57)
          hydra.retry_request?(request, response).should be_false
        end
      end
    end
  end
end

describe Xingfus::Hydra::Stubbing do
  shared_examples_for "any stubbable target" do
    before(:each) do
      @on_complete_handler_called = nil
      @request  = Xingfus::Request.new("http://localhost:3000/foo",
                                       :user_agent => 'test')
      @request.on_complete do |response|
        @on_complete_handler_called = true
        response.code.should == 404
        response.headers.should == "whatever"
      end
      @response = Xingfus::Response.new(:code => 404,
                                        :headers => "whatever",
                                        :body => "not found",
                                        :time => 0.1)
    end

    after(:each) do
      @stub_target.clear_stubs
    end

    it "should provide a stubs accessor" do
      begin
        @stub_target.stubs.should == []
        @stub_target.stubs = [:foo]
      ensure
        @stub_target.clear_stubs
      end
    end

    it "stubs requests to a specific URI" do
      @stub_target.stub(:get, "http://localhost:3000/foo",
                        :headers => { 'user-agent' => 'test'}).
                        and_return(@response)

      @hydra.queue(@request)
      @hydra.run
      @on_complete_handler_called.should be_true
      @response.request.should == @request
    end

    it "stubs requests to URIs matching a pattern" do
      @stub_target.stub(:get, /foo/,
                        :headers => { 'user-agent' => 'test' }).
                        and_return(@response)
      @hydra.queue(@request)
      @hydra.run
      @on_complete_handler_called.should be_true
      @response.request.should == @request
    end

    it "can clear stubs" do
      @stub_target.clear_stubs
    end

    it "can clear stubs with multiple exceptions" do
      [1,2].each do |index|
        request = Xingfus::Request.new("http://localhost:3000/foofoo/#{index}",
                                       :user_agent => 'test')
        response = Xingfus::Response.new(:code => 404,
                                         :headers => "whatever",
                                         :body => "not found #{index}",
                                         :time => 0.1)

        @stub_target.stub(:get, %r[/foofoo/#{index}]).and_return(response)

        request.on_complete do |response|
          raise "got a non success response #{response.code}" unless response.code / 100 == 2
        end

        @hydra.queue(request)
      end

      expect{ @hydra.run }.to raise_exception

      @hydra.clear_stubs

      expect{ @hydra.run }.to_not raise_exception
    end

    it "clears out previously queued requests once they are called" do
      @stub_target.stub(:get, "http://localhost:3000/asdf",
                        :headers => { 'user-agent' => 'test' }).
                        and_return(@response)

      call_count = 0
      request = Xingfus::Request.new("http://localhost:3000/asdf", :user_agent => 'test')
      request.on_complete do |response|
        call_count += 1
      end
      @hydra.queue(request)
      @hydra.run
      call_count.should == 1
      @hydra.run
      call_count.should == 1
    end

    it "calls stubs for requests that are queued up in the on_complete of a first stub" do
      @stub_target.stub(:get, "http://localhost:3000/asdf").and_return(@response)
      @stub_target.stub(:get, "http://localhost:3000/bar").and_return(@response)

      second_handler_called = false
      request = Xingfus::Request.new("http://localhost:3000/asdf")
      request.on_complete do |response|
        r = Xingfus::Request.new("http://localhost:3000/bar")
        r.on_complete do |res|
          second_handler_called = true
        end
        @hydra.queue(r)
      end
      @hydra.queue(request)
      @hydra.run

      second_handler_called.should be_true
    end
  end

  describe "global (class-level) stubbing" do
    before(:each) do
      @hydra = Xingfus::Hydra.new
      @stub_target = Xingfus::Hydra
    end

    it_should_behave_like "any stubbable target"
  end

  describe "instance stubbing" do
    before(:each) do
      @hydra = Xingfus::Hydra.new
      @stub_target = @hydra
    end

    it_should_behave_like "any stubbable target"
  end
end

describe Xingfus::Hydra::Callbacks do
  before(:all) do
    @klass = Xingfus::Hydra
  end

  describe "#after_request_before_on_complete" do
    it "should provide a global hook after a request" do
      begin
        http_method = nil
        @klass.after_request_before_on_complete do |request|
          http_method = request.method
        end

        hydra = @klass.new
        request = Xingfus::Request.new('http://localhost:3000',
                                       :method => :get)
        response = Xingfus::Response.new(:code => 404,
                                         :headers => "whatever",
                                         :body => "not found",
                                         :time => 0.1)
        hydra.stub(:get, 'http://localhost:3000').
          and_return(response)

        hydra.queue(request)
        hydra.run

        http_method.should == :get
      ensure
        @klass.clear_global_hooks
      end
    end
  end
end

describe Xingfus::Hydra::ConnectOptions do
  before(:all) do
    @klass = Xingfus::Hydra
  end

  let!(:old_net_connect) { @klass.allow_net_connect }
  let!(:old_ignore_localhost) { @klass.ignore_localhost }
  let(:hydra) { @klass.new }

  after(:each) do
    @klass.allow_net_connect = old_net_connect
    @klass.ignore_localhost = old_ignore_localhost
  end

  def request_for(host)
    Xingfus::Request.new("http://#{host}:3000")
  end

  describe "#ignore_localhost" do
    context "when set to true" do
      before(:each) { @klass.ignore_localhost = true }

      [true, false].each do |val|
        it "allows localhost requests when allow_net_connect is #{val}" do
          @klass.allow_net_connect = val
          expect { hydra.queue(request_for('localhost')) }.to_not raise_error
        end
      end
    end

    context "when set to false" do
      before(:each) { @klass.ignore_localhost = false }

      it "allows localhost requests when allow_net_connect is true" do
        @klass.allow_net_connect = true
        expect { hydra.queue(request_for('localhost')) }.to_not raise_error
      end

      it "does not allow localhost requests when allow_net_connect is false" do
        @klass.allow_net_connect = false
        expect { hydra.queue(request_for('localhost')) }.to raise_error(Xingfus::Hydra::NetConnectNotAllowedError)
      end
    end
  end

  describe "#ignore_hosts" do
    context 'when allow_net_connect is set to false' do
      before(:each) do
        @klass.ignore_localhost = false
        @klass.allow_net_connect = false
      end

      Xingfus::Request::LOCALHOST_ALIASES.each do |disallowed_host|
        ignore_hosts = Xingfus::Request::LOCALHOST_ALIASES - [disallowed_host]

        context "when set to #{ignore_hosts.join(' and ')}" do
          before(:each) { @klass.ignore_hosts = ignore_hosts }

          it "does not allow a request to #{disallowed_host}" do
            expect { hydra.queue(request_for(disallowed_host)) }.to raise_error(Xingfus::Hydra::NetConnectNotAllowedError)
          end

          ignore_hosts.each do |host|
            it "allows a request to #{host}" do
              expect { hydra.queue(request_for(host)) }.to_not raise_error
            end
          end
        end
      end
    end
  end

  describe "#allow_net_connect" do
    it "should be settable" do
      @klass.allow_net_connect = true
      @klass.allow_net_connect.should be_true
    end

    it "should default to true" do
      @klass.allow_net_connect.should be_true
    end

    it "should raise an error if we queue a request while its false" do
      @klass.allow_net_connect = false
      @klass.ignore_localhost = false

      expect {
        hydra.queue(request_for('example.com'))
      }.to raise_error(Xingfus::Hydra::NetConnectNotAllowedError)
    end
  end

  describe "#allow_net_connect?" do
    it "should return true by default" do
      @klass.allow_net_connect?.should be_true
    end
  end
end
