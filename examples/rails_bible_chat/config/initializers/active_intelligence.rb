# ActiveIntelligence Configuration

ActiveIntelligence.configure do |config|
  # Anthropic API Configuration
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']

  # Enable logging in development
  config.settings[:logger] = Rails.logger if Rails.env.development?
end

# Validate API key on initialization
if Rails.env.development? && ENV['ANTHROPIC_API_KEY'].blank?
  Rails.logger.warn "[ActiveIntelligence] ANTHROPIC_API_KEY is not configured. Set it in .env or environment variables."
end
