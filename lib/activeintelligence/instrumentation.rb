# lib/activeintelligence/instrumentation.rb
module ActiveIntelligence
  module Instrumentation
    class << self
      # Check if ActiveSupport::Notifications is available
      def available?
        defined?(ActiveSupport::Notifications) && Config.settings[:enable_notifications]
      end

      # Instrument a block of code
      def instrument(event_name, payload = {}, &block)
        return yield(payload) unless available?

        ActiveSupport::Notifications.instrument("#{event_name}.activeintelligence", payload, &block)
      end

      # Publish an event (fire-and-forget)
      def publish(event_name, payload = {})
        return unless available?

        ActiveSupport::Notifications.publish("#{event_name}.activeintelligence", Time.now, Time.now, SecureRandom.uuid, payload)
      end
    end
  end
end
