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
    config.autoload_paths << File.expand_path('models', __dir__)
    config.eager_load_paths << File.expand_path('models', __dir__)

    # Explicitly require models when engine loads
    initializer 'active_intelligence.load_models' do
      require_relative 'models/conversation'
      require_relative 'models/message'
      require_relative 'models/user_message'
      require_relative 'models/assistant_message'
      require_relative 'models/tool_message'
    end
  end
end
