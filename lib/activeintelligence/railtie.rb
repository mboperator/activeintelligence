module ActiveIntelligence
  class Railtie < Rails::Railtie
    railtie_name :active_intelligence

    # Add generators path
    generators do
      require 'generators/active_intelligence/install/install_generator'
    end

    # Optional: Add eager load paths
    config.eager_load_namespaces << ActiveIntelligence

    # Optional: Initialize configuration
    initializer 'active_intelligence.configuration' do |app|
      # Configuration initialization if needed
    end
  end
end
