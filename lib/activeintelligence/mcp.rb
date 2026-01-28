# frozen_string_literal: true

require_relative 'mcp/base_controller'

module ActiveIntelligence
  module MCP
    class Error < StandardError; end
    class ProtocolError < Error; end
    class AuthenticationError < Error; end
  end
end

# Load Rails integration if Rails is available
if defined?(Rails)
  require_relative 'mcp/rails_controller'
end
