module ActiveIntelligence
  # Base message class using Single Table Inheritance (STI)
  class Message < ActiveRecord::Base
    self.table_name = 'active_intelligence_messages'

    belongs_to :conversation, class_name: 'ActiveIntelligence::Conversation'

    validates :role, presence: true, inclusion: { in: %w[user assistant tool] }
    validates :type, presence: true

    scope :by_role, ->(role) { where(role: role) }

    # Serialize JSON fields if using databases that don't support JSON natively
    # (PostgreSQL, MySQL 5.7+, and SQLite 3.9+ support JSON natively)
    if ActiveRecord::VERSION::MAJOR < 7
      serialize :tool_calls, coder: JSON
      serialize :metadata, coder: JSON
    end

    # Set role automatically based on class type before validation
    before_validation :set_role_from_type

    private

    def set_role_from_type
      self.role = case self.class.name
                  when 'ActiveIntelligence::UserMessage'
                    'user'
                  when 'ActiveIntelligence::AssistantMessage'
                    'assistant'
                  when 'ActiveIntelligence::ToolMessage'
                    'tool'
                  else
                    role # Keep existing role for base class
                  end
    end
  end
end
