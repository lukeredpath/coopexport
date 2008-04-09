require 'mocha'

$: << File.join(File.dirname(__FILE__), *%w[.. lib])

Spec::Runner.configure do |config|
  config.mock_with :mocha
end