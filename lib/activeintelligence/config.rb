# lib/active_intelligence/config.rb
require 'logger'

module ActiveIntelligence
  module Config
    # Default configurations
    @settings = {
      claude: {
        model: "claude-3-opus-20240229",
        api_version: "2023-06-01",
        max_tokens: 4096,
        enable_prompt_caching: true
      },
      retry: {
        max_retries: 3,           # Maximum number of retry attempts
        base_delay: 1.0,          # Initial delay in seconds
        max_delay: 60.0,          # Maximum delay in seconds
        backoff_factor: 2.0,      # Exponential backoff multiplier
        retryable_errors: [429, 500, 502, 503, 504]  # HTTP status codes to retry
      },
      logger: defined?(Rails) ? Rails.logger : Logger.new(STDOUT)
    }

    class << self
      attr_accessor :settings

      def method_missing(method, *args)
        if method.to_s.end_with?('=')
          key = method.to_s.chop.to_sym
          @settings[key] = args.first
        else
          @settings[method]
        end
      end

      def respond_to_missing?(method, include_private = false)
        @settings.key?(method.to_s.chop.to_sym) || @settings.key?(method) || super
      end
    end
  end
end