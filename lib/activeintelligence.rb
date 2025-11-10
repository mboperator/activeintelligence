# lib/active_intelligence.rb
require_relative 'activeintelligence/config'
require_relative 'activeintelligence/agent'
require_relative 'activeintelligence/messages'
require_relative 'activeintelligence/api_clients/base_client'
require_relative 'activeintelligence/api_clients/claude_client'
require_relative 'activeintelligence/tool'
require_relative 'activeintelligence/errors'

# Load Rails Engine if Rails is present
if defined?(Rails)
  require_relative 'activeintelligence/engine'
end

module ActiveIntelligence
  class Error < StandardError; end
  class ApiError < Error; end
  class ConfigurationError < Error; end

  # Allow configuration through a block
  def self.configure
    yield(Config)
  end

  # Get current configuration
  def self.config
    Config
  end
end
