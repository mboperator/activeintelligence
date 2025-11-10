# Load ActiveIntelligence models explicitly to avoid namespace conflicts
# This ensures the models are available before controllers try to use them

Rails.application.config.after_initialize do
  # Explicitly load the models to ensure they're available
  unless Rails.application.config.cache_classes
    Rails.application.reloader.to_prepare do
      load Rails.root.join('app/models/active_intelligence.rb')
      load Rails.root.join('app/models/active_intelligence/message.rb')
      load Rails.root.join('app/models/active_intelligence/conversation.rb')
    end
  else
    # In production, just require once
    require Rails.root.join('app/models/active_intelligence')
    require Rails.root.join('app/models/active_intelligence/message')
    require Rails.root.join('app/models/active_intelligence/conversation')
  end
end
