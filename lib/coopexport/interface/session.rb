require 'net/http'

module CoopExport
  module Interface
    class Session
      attr_reader :security_token
      
      SECURITY_TOKEN_KEY = 'org.apache.struts.taglib.html.TOKEN'
      
      def initialize(connection, response_parser = ResponseParser.new)
        @connection = connection
        @security_token = nil
        @response_parser = response_parser
      end
      
      def request(request_object)
        response = @connection.request(request_object)
        if response.code == '200'
          @security_token = @response_parser.find_security_token(response.body)
        end
        return response
      end
      
      def get(path, params)
        query_string = query_string_from_params( secure_params(params) )
        request_uri = URI::HTTP.build(:path => path, :query => query_string).request_uri
        get_request = Net::HTTP::Get.new(request_uri)
        request(get_request)
      end
      
      def post(path, params)
        post_request = Net::HTTP::Post.new(path)
        post_request.set_form_data(secure_params(params))
        request(post_request)
      end
      
      private
        def secure_params(params)
          params.merge(SECURITY_TOKEN_KEY => security_token)
        end
        
        def query_string_from_params(param_hash)
          param_hash.inject([]) { |params, (key, value)| params << "#{key}=#{value}" }.sort.join('&')
        end
    end
    
    class ResponseParser
      def find_security_token(html_content)
        
      end
    end
  end
end