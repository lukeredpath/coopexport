require File.join(File.dirname(__FILE__), *%w[.. spec_helper])

require 'coopexport/interface/session'

describe "A new session" do
  before :each do
    @session = CoopExport::Interface::Session.new(stub('connection'))
  end
  
  it "should have no security token" do
    @session.security_token.should be_nil
  end
end

describe "A session, when sending a request" do
  before :each do
    @connection = mock('connection')
    @response_parser = stub('response parser')
    @session = CoopExport::Interface::Session.new(@connection, @response_parser)
  end
  
  it "should send the specified request using the available connection" do
    request = stub('request')
    @connection.expects(:request).with(request).returns(stub_everything('response'))
    @session.request(request)
  end
  
  it "should parse the response body and store the new security token if a 200 response is returned" do
    response = stub('http response', :body => 'html content', :code => '200')
    @connection.stubs(:request).returns(response)
    @response_parser.stubs(:find_security_token).with('html content').returns('NEW_SECURITY_TOKEN')
    @session.request(stub)
    @session.security_token.should == 'NEW_SECURITY_TOKEN'
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