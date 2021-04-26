# -*- coding: utf-8 -*-
require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Xingfus::Easy do
  describe "#supports_zlib" do
    before(:each) do
      @easy = Xingfus::Easy.new
    end

    it "should return true if the version string has zlib" do
      @easy.stub(:curl_version).and_return("libcurl/7.20.0 OpenSSL/0.9.8l zlib/1.2.3 libidn/1.16")
      @easy.supports_zlib?.should be_true
    end

    it "should return false if the version string doesn't have zlib" do
      @easy.stub(:curl_version).and_return("libcurl/7.20.0 OpenSSL/0.9.8l libidn/1.16")
      @easy.supports_zlib?.should be_false
    end
  end

  describe "curl errors" do
    it "should provide the CURLE_OPERATION_TIMEDOUT return code when a request times out" do
      e = Xingfus::Easy.new
      e.url = "http://localhost:3001/?delay=1"
      e.method = :get
      e.timeout = 100
      e.perform
      e.curl_return_code.should == 28
      e.curl_error_message.should == "Timeout was reached"
      e.response_code.should == 0
    end

    it "should provide the CURLE_COULDNT_CONNECT return code when trying to connect to a non existent port" do
      e = Xingfus::Easy.new
      e.url = "http://localhost:3999"
      e.method = :get
      e.connect_timeout = 100
      e.perform
      e.curl_return_code.should == 7
      e.curl_error_message.should == "Couldn't connect to server"
      e.response_code.should == 0
    end

    it "should not return an error message on a successful easy operation" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :get
      easy.curl_error_message.should == nil
      easy.perform
      easy.response_code.should == 200
      easy.curl_return_code.should == 0
      easy.curl_error_message.should == "No error"
    end

  end

  describe "options" do
    it "should not follow redirects if not instructed to" do
      e = Xingfus::Easy.new
      e.url = "http://localhost:3001/redirect"
      e.method = :get
      e.perform
      e.response_code.should == 302
    end

    it "should allow for following redirects" do
      e = Xingfus::Easy.new
      e.url = "http://localhost:3001/redirect"
      e.method = :get
      e.follow_location = true
      e.perform
      e.response_code.should == 200
      JSON.parse(e.response_body)["REQUEST_METHOD"].should == "GET"
    end

    it "should allow you to set the user agent" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :get
      easy.user_agent = "myapp"
      easy.perform
      easy.response_code.should == 200
      JSON.parse(easy.response_body)["HTTP_USER_AGENT"].should == "myapp"
    end

    it "should provide a timeout in milliseconds" do
      e = Xingfus::Easy.new
      e.url = "http://localhost:3001/?delay=1"
      e.method = :get
      e.timeout = 10
      start_time = Time.now
      e.perform
      run_time = Time.now - start_time
      e.timed_out?.should == true
      run_time.should < 0.2
    end

    it "should allow the setting of the max redirects to follow" do
      e = Xingfus::Easy.new
      e.url = "http://localhost:3001/redirect"
      e.method = :get
      e.follow_location = true
      e.max_redirects = 5
      e.perform
      e.response_code.should == 200
    end

    it "should handle our bad redirect action, provided we've set max_redirects properly" do
      e = Xingfus::Easy.new
      e.url = "http://localhost:3001/bad_redirect"
      e.method = :get
      e.follow_location = true
      e.max_redirects = 5
      e.perform
      e.response_code.should == 302
    end
  end
  
  describe "authentication" do
    it "should allow to set username and password" do
      e = Xingfus::Easy.new
      username, password = 'foo', 'bar'
      e.auth = { :username => username, :password => password }
      e.url = "http://localhost:3001/auth_basic/#{username}/#{password}"
      e.method = :get
      e.perform
      e.response_code.should == 200
    end
    
    it "should allow to query auth methods support by the server" do
      e = Xingfus::Easy.new
      e.url = "http://localhost:3001/auth_basic/foo/bar"
      e.method = :get
      e.perform
      e.auth_methods.should == Xingfus::Easy::AUTH_TYPES[:CURLAUTH_BASIC]
    end

    it "should allow to set authentication method" do
      e = Xingfus::Easy.new
      e.auth = { :username => 'username', :password => 'password', :method => Xingfus::Easy::AUTH_TYPES[:CURLAUTH_NTLM] }
      e.url = "http://localhost:3001/auth_ntlm"
      e.method = :get
      e.perform
      e.response_code.should == 200
    end
  end
  
  describe "get" do
    it "should perform a get" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :get
      easy.perform
      easy.response_code.should == 200
      JSON.parse(easy.response_body)["REQUEST_METHOD"].should == "GET"
    end
  end

  describe "purge" do
    it "should set custom request to purge" do
      easy = Xingfus::Easy.new
      easy.should_receive(:set_option).with(Xingfus::Easy::OPTION_VALUES[:CURLOPT_CUSTOMREQUEST], "PURGE").once
      easy.method = :purge
    end
  end

  describe "head" do
    it "should perform a head" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :head
      easy.perform
      easy.response_code.should == 200
    end
  end

  describe "start_time" do
    it "should be get/settable" do
      time = Time.now
      easy = Xingfus::Easy.new
      easy.start_time.should be_nil
      easy.start_time = time
      easy.start_time.should == time
    end
  end

  describe "params=" do
    it "should handle arrays of params" do
      easy = Xingfus::Easy.new
      easy.url = "http://localhost:3002/index.html"
      easy.method = :get
      easy.request_body = "this is a body!"
      easy.params = {
        :foo => 'bar',
        :username => ['dbalatero', 'dbalatero2']
      }
      easy.url.should =~ /\?.*foo=bar&username=dbalatero&username=dbalatero2/
    end
  end


  describe "put" do
    it "should perform a put" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :put
      easy.perform
      easy.response_code.should == 200
      JSON.parse(easy.response_body)["REQUEST_METHOD"].should == "PUT"
    end
    
    it "should send a request body" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :put
      easy.request_body = "this is a body!"
      easy.perform
      easy.response_code.should == 200
      easy.response_body.should include("this is a body!")
    end

    it "should send a large request body" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :put
      easy.request_body = "1" * 2000
      easy.perform
      easy.response_code.should == 200
      easy.response_body.should include("1" * 2000)
    end

    it "should be able perform put with empty bodies on the same easy handle" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :put
      easy.perform
      easy.response_code.should == 200
      JSON.parse(easy.response_body)["REQUEST_METHOD"].should == "PUT"

      easy.reset

      easy.url    = "http://localhost:3002"
      easy.method = :put
      easy.perform
      easy.response_code.should == 200
      JSON.parse(easy.response_body)["REQUEST_METHOD"].should == "PUT"
    end

  end
  
  describe "post" do
    it "should perform a post" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :post
      easy.perform
      easy.response_code.should == 200
      JSON.parse(easy.response_body)["REQUEST_METHOD"].should == "POST"
    end
    
    it "should send a request body" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :post
      easy.request_body = "this is a body!"
      easy.perform
      easy.response_code.should == 200
      easy.response_body.should include("this is a body!")
    end

    it "should send a large request body" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :post
      easy.request_body = "1" * 2000
      easy.perform
      easy.response_code.should == 200
      easy.response_body.should include("1" * 2000)
    end

    it "should handle params" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :post
      easy.params = {:foo => "bar"}
      easy.perform
      easy.response_code.should == 200
      easy.response_body.should =~ /foo=bar/
    end

    it "should use Content-Type: application/x-www-form-urlencoded for normal posts" do
      easy = Xingfus::Easy.new
      easy.url = "http://localhost:3002/normal_post"
      easy.method = :post
      easy.params = { :a => 'b', :c => 'd',
                      :e => { :f => { :g => 'h' } } }
      easy.perform

      request = JSON.parse(easy.response_body)
      request['CONTENT_TYPE'].should == 'application/x-www-form-urlencoded'
      request['rack.request.form_vars'].should == 'a=b&c=d&e%5Bf%5D%5Bg%5D=h'
    end

    it "should properly encode values in the post body" do
      easy = Xingfus::Easy.new
      easy.url = "http://localhost:3002/normal_post"
      easy.method = :post

      easy.params = {:a => "a=b&c\nx x", :b => 2}
      easy.perform

      request = JSON.parse(easy.response_body)
      request['CONTENT_TYPE'].should == 'application/x-www-form-urlencoded'

      request['rack.request.form_vars'].should == 'a=a%3Db%26c%0Ax+x&b=2'
    end

    it "should set content length correctly for a utf-8 string" do
      body = "this is a body with utf-8 content: Motörhead!  WHÖÖ!"
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :post
      easy.should_receive(:set_option).with(Xingfus::Easy::OPTION_VALUES[:CURLOPT_POSTFIELDSIZE], 55)
      easy.should_receive(:set_option).with(Xingfus::Easy::OPTION_VALUES[:CURLOPT_COPYPOSTFIELDS], body)
      easy.request_body = body
    end

    it "should handle a file upload, as multipart" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002/file"
      easy.method = :post
      easy.params = {:file => File.open(File.expand_path(File.dirname(__FILE__) + "/../fixtures/placeholder.txt"), "r")}
      easy.perform
      easy.response_code.should == 200
      result = JSON.parse(easy.response_body)
      
      { 'content-type' => 'text/plain',
        'filename' => 'placeholder.txt',
        'content' => 'This file is used to test uploading.'
      }.each do |key, val|
        result[key].should == val
      end

      result['request-content-type'].should =~ /multipart/
    end

    it "should not encode parameters when multipart" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002/file"
      easy.method = :post
      easy.params = {:other => "abc def", :file => File.open(File.expand_path(File.dirname(__FILE__) + "/../fixtures/placeholder.txt"), "r")}
      easy.perform
      easy.response_code.should == 200
      result = JSON.parse(easy.response_body)
      result['other'].should == 'abc def'
    end
  end
  
  describe "delete" do
    it "should perform a delete" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :delete
      easy.perform
      easy.response_code.should == 200
      JSON.parse(easy.response_body)["REQUEST_METHOD"].should == "DELETE"
    end
    
    it "should send a request body" do
      easy = Xingfus::Easy.new
      easy.url    = "http://localhost:3002"
      easy.method = :delete
      easy.request_body = "this is a body!"
      easy.perform
      easy.response_code.should == 200
      easy.response_body.should include("this is a body!")
    end
  end
  
  describe "encoding/compression support" do
    
    it "should send valid encoding headers and decode the response" do
      easy = Xingfus::Easy.new
      easy.url = "http://localhost:3002/gzipped"
      easy.method = :get
      easy.perform
      easy.response_code.should == 200
      JSON.parse(easy.response_body)["HTTP_ACCEPT_ENCODING"].should == "deflate, gzip"
    end

    it "should send valid encoding headers and decode the response after reset" do
      easy = Xingfus::Easy.new
      easy.reset
      easy.url = "http://localhost:3002/gzipped"
      easy.method = :get
      easy.perform
      easy.response_code.should == 200
      JSON.parse(easy.response_body)["HTTP_ACCEPT_ENCODING"].should == "deflate, gzip"
    end
    
  end
end
