# lib/active_intelligence.rb
require_relative 'activeintelligence/config'
require_relative 'activeintelligence/agent'
require_relative 'activeintelligence/messages'
require_relative 'activeintelligence/api_clients/base_client'
require_relative 'activeintelligence/api_clients/claude_client'
require_relative 'activeintelligence/tool'
require_relative 'activeintelligence/errors'

module ActiveIntelligence
  class Error < StandardError; end
  class ApiError < Error; end
  class ConfigurationError < Error; end

  # Allow configuration through a block
  def self.configure
    yield(Config)
  end
end
