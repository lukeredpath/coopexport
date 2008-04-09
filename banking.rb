require 'net/http'
require 'net/https'
require 'open-uri'
require 'hpricot'

class IPLookup
  class << self
    def lookup(reload=false)
      if reload
        @ip = perform_lookup
      else
        @ip ||= perform_lookup
      end
    end
    
    def perform_lookup
      open("http://myip.dk") do |f|
        /([0-9]{1,3}\.){3}[0-9]{1,3}/.match(f.read)[0].to_a[0]
      end
    end
  end
end

module Banking
    
  BANKING_URL = 'welcome27.co-operativebank.co.uk'
  RESET_SESSION_PATH = '/CBIBSWeb/start.do'
  LOGIN_PATH = '/CBIBSWeb/login.do'
  SECURITY_CHECK_PATH = '/CBIBSWeb/loginSpi.do'
  TIMEOUT_MESSAGE = /you have been logged out/
  HTTP_REFERER = "https://#{BANKING_URL}#{RESET_SESSION_PATH}"
  SECURITY_TOKEN_NAME = 'org.apache.struts.taglib.html.TOKEN'

  def self.default_connection(debug_output=nil)
    connection = Net::HTTP.new(BANKING_URL, 443)
    connection.use_ssl = true
    connection.set_debug_output(debug_output) unless debug_output.nil?
    connection
  end
  
  def self.default_session(debug_output=nil)
    connection = default_connection(debug_output)
    connection.start
    Session.new(connection)
  end
  
  class Session
    attr_reader :session_id, :security_token
    
    def initialize(http_connection)
      @connection = http_connection
      @authenticated = false
    end
    
    def reset!
      response = @connection.get(Banking::RESET_SESSION_PATH)
      @session_id = response['set-cookie']
      @security_token = SecurityTokenParser.parse(response.body)
      @authenticated = false
    end
    
    def cookie
      "cfswebcookie=#{IPLookup.lookup}.64551182761143299; #{session_id}"
    end
    
    def authenticated?
      @authenticated
    end
    
    def authenticated!
      @authenticated = true
    end
    
    def post(path, params_hash)
      params = params_hash.merge(Banking::SECURITY_TOKEN_NAME => security_token).to_params
      headers = { 'Cookie' => cookie, 'Referer' => Banking::HTTP_REFERER }
      @connection.post(path, params, headers)
    end
    
    def login(sort_code, account_number, security_code)
      reset! if (session_id.nil? || security_token.nil?)
      LoginCommand.new(self).execute(sort_code, account_number, security_code)
    end
    
    def update_security_token(new_token)
      @security_token = new_token
    end
  end
  
  class LoginCommand    
    MAX_ATTEMPTS = 3
    
    def initialize(session)
      @session = session
      @login_attempts = 0
    end
    
    def execute(sort_code, account_number, security_code)
       response = @session.post(Banking::LOGIN_PATH, {
         :sortCode => sort_code,
         :accountNumber => account_number,
         :passNumber => security_code
       })
       if LoginResponseParser.success?(response)
         return SecurityCheck.process(response, @session)
       else
         raise AuthenticationError
       end
     rescue SessionTimeout
       @login_attempts = @login_attempts.succ
       raise SessionError if maximum_attempts_reached?
       @session.reset!
       retry
    end
    
    protected
      def successful?(response)
        LoginResponseParser.parse(response)
      end
    
      def maximum_attempts_reached?
        @login_attempts == MAX_ATTEMPTS
      end
      
      def reset_cookie
        session_data = Banking.reset_session(@conn)
        @security_token = session_data[:token]
        @cookie = Banking.generate_cookie(session_data[:session_id])
      end
      
      def standard_headers
        { 'Cookie' => @cookie,
          'User-Agent' => Banking::USER_AGENT,
          'Referer' => Banking::HTTP_REFERER }
      end
  end
  
  class LoginResponseParser
    def initialize(http_response)
      @response = http_response
    end
    
    def successful?
      body = @response.body
      raise SessionTimeout if body =~ Banking::TIMEOUT_MESSAGE
      body =~ /Security Information/
    end
    
    class << self
      def success?(http_response)
        new(http_response).successful?
      end
    end
  end
  
  class SecurityTokenParser
    def initialize(login_page_html)
      @html = login_page_html
    end
    
    def self.parse(login_page_html)
      new(login_page_html).security_token
    end
    
    def security_token
      parser.search("//input[@name='#{Banking::SECURITY_TOKEN_NAME}']").first['value']
    end
    
    protected
      def parser
        Hpricot(@html)
      end
  end
  
  class SecurityCheck
    class << self
      attr_reader :fields, :description
      
      def process(http_response, session)
        response_body = http_response.body
        check = case response_body
          when /Memorable date/
            MemorableDateCheck.new(session)
          when /Place of Birth/
            BirthplaceCheck.new(session)
          when /firstschool/
            FirstSchoolCheck.new(session)
          when /lastschool/
            LastSchoolCheck.new(session)
          when /Memorable name/
            MemorableNameCheck.new(session)
        else
          raise UnknownSecurityCheckError
        end
        unless check.nil?
          new_security_token = SecurityTokenParser.parse(response_body)
          session.update_security_token(new_security_token)
          return check
        end
      end
      
      def set_fields(*fields)
        @fields = fields
      end
      
      def set_description(description)
        @description = description
      end
      
    end
    
    def initialize(session)
      @session = session
    end
    
    def execute(*args)
      response = @session.post(Banking::SECURITY_CHECK_PATH, security_params(args))
      SecurityResponseCheck.process(response, @session)
      @session.authenticated?
    end
    
    def to_s
      description
    end
    
    def description
      self.class.description
    end
    
    def fields
      self.class.fields
    end
    
    protected
      def security_params(args)
        params = {}
        args.each_with_index do |arg, index|
          params[fields[index]] = arg
        end
        params
      end
  end
  
  class MemorableDateCheck < SecurityCheck
    set_description 'memorable date'
    set_fields :memorableDay, :memorableMonth, :memorableYear
  end
  
  class BirthplaceCheck < SecurityCheck
    set_description 'place of birth'
    set_fields :birthPlace
  end
  
  class LastSchoolCheck < SecurityCheck
    set_description 'last school attended'
    set_fields :lastSchool
  end
  
  class FirstSchoolCheck < SecurityCheck
    set_description 'first school attended'
    set_fields :firstSchool
  end
  
  class MemorableNameCheck < SecurityCheck
    set_description 'memorable name'
    set_fields :memorableName
  end
  
  class SecurityResponseCheck
    def initialize(response)
      @response = response
    end
    
    def successful?
      body = @response.body
      #raise SessionTimeout if body =~ Banking::TIMEOUT_MESSAGE
      body =~ /Your Accounts/
    end
    
    def self.process(response, session)
      check = new(response)
      session.authenticated! if check.successful?
    end
  end
  
  class AuthenticationError < RuntimeError; end
  class SessionTimeout < RuntimeError; end
  class SessionError < RuntimeError; end
  class UnknownSecurityCheckError < RuntimeError; end
  
  module HashExtensions
    def to_params
      map { |key, value| "#{key}=#{value}" }.sort.join('&')
    end
  end
end

Hash.send(:include, Banking::HashExtensions)