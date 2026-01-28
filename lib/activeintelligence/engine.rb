require 'rails'

module ActiveIntelligence
  class Engine < ::Rails::Engine
    isolate_namespace ActiveIntelligence

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: 'spec/factories'
    end

    # The models directory contains ActiveRecord models that define constants
    # directly in the ActiveIntelligence namespace (not ActiveIntelligence::Models::).
    # We use Zeitwerk's push_dir to map the directory to the correct namespace.
    MODELS_PATH = File.expand_path('models', __dir__)

    # Use push_dir instead of collapse to explicitly map models/ -> ActiveIntelligence::
    # This must be done before autoloaders.setup is called
    initializer 'active_intelligence.configure_autoloader', before: :set_autoload_paths do
      Rails.autoloaders.main.push_dir(MODELS_PATH, namespace: ActiveIntelligence)
    end
  end
end
