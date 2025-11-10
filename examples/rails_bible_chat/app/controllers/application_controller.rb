class ApplicationController < ActionController::Base
  # Disable CSRF for this example (in production, use proper CSRF protection)
  skip_before_action :verify_authenticity_token
end
