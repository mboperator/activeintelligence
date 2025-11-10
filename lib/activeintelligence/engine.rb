require 'rails'

module ActiveIntelligence
  class Engine < ::Rails::Engine
    isolate_namespace ActiveIntelligence

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: 'spec/factories'
    end

    # Ensure models are autoloaded
    config.autoload_paths << File.expand_path('../models', __dir__)
  end
end
