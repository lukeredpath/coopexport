require 'net/https'

module CoopExport
  module Interface
    COOP_HOSTNAME = 'welcome26.co-operativebank.co.uk'
    
    def self.default_connection
      connection = Net::HTTP.new(COOP_HOSTNAME, 443)
      connection.use_ssl = true
      connection
    end
  end
end