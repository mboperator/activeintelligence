require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"

Bundler.require(*Rails.groups)

module RailsBibleChat
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = false

    # Ensure all custom paths are eager loaded
    config.eager_load_paths << Rails.root.join("app", "agents")
    config.eager_load_paths << Rails.root.join("app", "tools")
  end
end
