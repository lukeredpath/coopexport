require File.join(File.dirname(__FILE__), *%w[.. spec_helper])

require 'coopexport/interface/session'

describe "A new session" do
  before :each do
    @session = CoopExport::Interface::Session.new(stub('connection'))
  end
  
  it "should have no security token" do
    @session.security_token.should be_nil
  end
  
  it "should have no cookie" do
    @session.cookie.should be_nil
  end
  
  it "should have no previous request URI" do
    @session.previous_request_uri.should be_nil
  end
end

describe "A session, when sending a request" do
  before :each do
    @connection = stub('connection', :address => 'example.com')
    @response_parser = stub('response parser')
    @session = CoopExport::Interface::Session.new(@connection, @response_parser)
  end
  
  it "should send the specified request using the available connection and return the HTTP response" do
    request = stub_everything('request', :path => '/foo')
    http_response = stub_everything('response', :header => {})
    @connection.expects(:request).with(request).returns(http_response)
    @session.request(request).should == http_response
  end
  
  it "should add the Cookie header using the stored cookie value before dispatching" do
    @session.stubs(:cookie).returns('EXISTING_COOKIE_VALUE')
    request = stub_everything('request', :path => '/foo')
    request.expects(:add_field).with('Cookie', 'EXISTING_COOKIE_VALUE')
    @connection.stubs(:request).returns(stub_everything('response', :header => {}))
    @session.request(request)
  end
  
  it "should add the Referer header using the previous URI as a string before dispatching" do
    @session.stubs(:previous_request_uri).returns(stub('uri', :to_s => 'http://example.com/foo'))
    request = stub_everything('request', :path => '/foo')
    request.expects(:add_field).with('Referer', 'http://example.com/foo')
    @connection.stubs(:request).returns(stub_everything('response', :header => {}))
    @session.request(request)
  end
  
  it "should parse the response body and store the new security token if a 200 response is returned" do
    response = stub('http response', :body => 'html content', :code => '200', :header => {})
    @connection.stubs(:request).returns(response)
    @response_parser.stubs(:find_security_token).with('html content').returns('NEW_SECURITY_TOKEN')
    @session.request(stub_everything('request', :path => '/foo'))
    @session.security_token.should == 'NEW_SECURITY_TOKEN'
  end
  
  it "should store the cookie returned in the set-cookie response header" do
    response = stub('http response', :header => {'set-cookie' => 'JSESSIONID=1234'}, :code => nil)
    @connection.stubs(:request).returns(response)
    @session.request(stub_everything('request', :path => '/foo'))
    @session.cookie.should == 'JSESSIONID=1234'
  end
  
  it "should store the current request URI without query parameters" do
    URI::HTTP.stubs(:build).with(:host => 'example.com', :path => '/foo').returns(uri = stub)
    @connection.stubs(:request).returns(stub_everything('response', :header => {}))
    @session.request(stub_everything('http request', :path => '/foo?bar=baz'))
    @session.previous_request_uri.should == uri
  end
end

describe "A session, in general" do
  before :each do
    @session = CoopExport::Interface::Session.new(stub('connection'))
    @session.stubs(:security_token).returns('CURRENT_TOKEN')
  end
  
  it "should append the current security token to form data when sending POST" do
    post_params = {'param_one' => 'foo', 'param_two' => 'bar'}
    Net::HTTP::Post.stubs(:new).with('/path').returns(post_request = stub)
    post_request.expects(:set_form_data).with(post_params.merge('org.apache.struts.taglib.html.TOKEN' => 'CURRENT_TOKEN'))
    @session.expects(:request).with(post_request)
    @session.post('/path', post_params)
  end
  
  it "should append the current security token to query parameters when sending GET" do
    get_params = {'a' => 'foo', 'b' => 'bar'}
    Net::HTTP::Get.stubs(:new).with('/path?a=foo&b=bar&org.apache.struts.taglib.html.TOKEN=CURRENT_TOKEN').returns(get_request = stub)
    @session.expects(:request).with(get_request)
    @session.get('/path', get_params)
  end
end