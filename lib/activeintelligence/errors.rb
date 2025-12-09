# lib/active_intelligence/errors.rb
module ActiveIntelligence
  # Base error class
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ApiError < Error; end

  # API rate limit error with retry information
  class ApiRateLimitError < ApiError
    attr_reader :retry_after, :rate_limit_type, :request_id, :headers

    def initialize(message = "Rate limit exceeded", retry_after: nil, rate_limit_type: nil, request_id: nil, headers: {})
      @retry_after = retry_after
      @rate_limit_type = rate_limit_type
      @request_id = request_id
      @headers = headers
      super(message)
    end

    # Returns true if we know how long to wait
    def retry_after?
      !@retry_after.nil? && @retry_after > 0
    end

    def to_h
      {
        error: true,
        type: :rate_limit,
        message: message,
        retry_after: retry_after,
        rate_limit_type: rate_limit_type,
        request_id: request_id
      }
    end
  end

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