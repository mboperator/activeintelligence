# ActiveIntelligence Configuration

ActiveIntelligence.configure do |config|
  # Anthropic API Configuration
  # Set your API key in environment variables or Rails credentials
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY'] || Rails.application.credentials.dig(:anthropic, :api_key)

  # API Version
  # Default: "2023-06-01"
  # config.anthropic_version = "2023-06-01"

  # Default Model
  # Options: :claude_opus, :claude_sonnet, :claude_haiku
  # config.default_model = :claude_sonnet

  # Max Tokens
  # Maximum tokens for API responses
  # config.max_tokens = 1024

  # Logging
  # Enable/disable logging
  # config.enable_logging = Rails.env.development?

  # Timeout Settings (in seconds)
  # config.api_timeout = 60
  # config.streaming_timeout = 120
end

# Validate API key on initialization in production
if Rails.env.production? && ActiveIntelligence.config.anthropic_api_key.blank?
  Rails.logger.warn "[ActiveIntelligence] ANTHROPIC_API_KEY is not configured. Set it in environment variables or Rails credentials."
end
