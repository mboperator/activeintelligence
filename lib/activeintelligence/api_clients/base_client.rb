# lib/active_intelligence/api_clients/base_client.rb
require 'net/http'
require 'json'
require 'logger'
require 'pry'
module ActiveIntelligence
  module ApiClients
    class BaseClient
      attr_reader :logger

      def initialize(options = {})
        @logger = options[:logger] || Config.logger
      end

      def call(messages, system_prompt, options = {})
        raise NotImplementedError, "Subclasses must implement this method"
      end

      def call_streaming(messages, system_prompt, options = {}, &block)
        raise NotImplementedError, "Subclasses must implement this method"
      end

      protected

      def handle_error(error, prefix = "API Error")
        message = "#{prefix}: #{error.message}"
        logger.error(message)
        message
      end

      def safe_parse_json(data)
        JSON.parse(data)
      rescue JSON::ParserError => e
        logger.warn("JSON parse error: #{e.message}")
        nil
      end
    end
  end
end