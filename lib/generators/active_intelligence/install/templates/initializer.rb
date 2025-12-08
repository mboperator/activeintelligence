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
  # config.max_tokens = 4096

  # Logging
  # Enable/disable logging
  # config.enable_logging = Rails.env.development?

  # Timeout Settings (in seconds)
  # config.api_timeout = 60
  # config.streaming_timeout = 300

  # Rate Limiting & Retry Configuration
  # Automatic retry with exponential backoff for rate limit (429) and server errors
  # config.retry_max_retries = 3        # Maximum retry attempts (set to 0 to disable)
  # config.retry_base_delay = 1.0       # Initial delay in seconds
  # config.retry_max_delay = 60.0       # Maximum delay cap in seconds
  # config.retry_backoff_factor = 2.0   # Exponential backoff multiplier
end

# Validate API key on initialization in production
if Rails.env.production? && ActiveIntelligence.config.anthropic_api_key.blank?
  Rails.logger.warn "[ActiveIntelligence] ANTHROPIC_API_KEY is not configured. Set it in environment variables or Rails credentials."
end
