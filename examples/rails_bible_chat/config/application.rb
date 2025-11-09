require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module RailsBibleChat
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = false
    config.eager_load_paths << Rails.root.join("app", "agents")
    config.eager_load_paths << Rails.root.join("app", "tools")
  end
end
