# lib/active_intelligence/errors.rb
module ActiveIntelligence
  # Base error class
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ApiError < Error; end

  # Tool-related errors
  class ToolError < Error
    attr_reader :status, :details

    def initialize(message = "Tool execution failed", status: :error, details: {})
      @status = status
      @details = details
      super(message)
    end

    # Convert to a format suitable for returning to the LLM
    def to_response
      {
        error: true,
        message: message,
        status: status,
        details: details
      }
    end
  end

  # Specific tool error types
  class InvalidParameterError < ToolError; end
  class ExternalServiceError < ToolError; end
  class RateLimitError < ToolError; end
  class AuthenticationError < ToolError; end
end