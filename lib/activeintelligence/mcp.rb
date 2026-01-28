# frozen_string_literal: true

module ActiveIntelligence
  module MCP
    class Error < StandardError; end
    class ProtocolError < Error; end
    class AuthenticationError < Error; end
  end
end

# Only load the BaseController if Rails/ActionController is available
# since it inherits from ActionController::API
if defined?(ActionController::API)
  require_relative 'mcp/base_controller'
end
