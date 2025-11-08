# lib/active_intelligence/config.rb
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