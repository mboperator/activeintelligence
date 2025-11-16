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
      logger: defined?(Rails) ? Rails.logger : Logger.new(STDOUT),
      # Observability settings
      log_level: :info,              # :debug, :info, :warn, :error
      log_api_requests: false,       # Log full API request/response details
      log_tool_executions: true,     # Log tool call executions
      log_token_usage: true,         # Log token consumption and costs
      structured_logging: true,      # Use JSON structured logging
      enable_notifications: true     # Enable ActiveSupport::Notifications instrumentation
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

      # Helper method for structured logging
      def log(level, message_or_hash, additional_data = {})
        return unless logger

        if @settings[:structured_logging] && (message_or_hash.is_a?(Hash) || !additional_data.empty?)
          data = message_or_hash.is_a?(Hash) ? message_or_hash : { message: message_or_hash }.merge(additional_data)
          data[:timestamp] = Time.now.iso8601
          logger.send(level, data.to_json)
        else
          logger.send(level, message_or_hash)
        end
      end
    end
  end
end