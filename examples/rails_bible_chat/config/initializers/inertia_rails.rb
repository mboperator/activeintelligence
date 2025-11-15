InertiaRails.configure do |config|
  # Set the version of your assets
  config.version = ViteRuby.digest

  # Configure which layout to use for Inertia responses
  config.layout = 'application'
end
