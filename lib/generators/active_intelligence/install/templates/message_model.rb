module ActiveIntelligence
  class Message < ApplicationRecord
    self.table_name = 'active_intelligence_messages'

    belongs_to :conversation, class_name: 'ActiveIntelligence::Conversation'

    validates :role, presence: true, inclusion: { in: %w[user assistant tool] }
    validates :content, presence: true, if: -> { role != 'tool' }

    scope :by_role, ->(role) { where(role: role) }
    scope :user_messages, -> { where(role: 'user') }
    scope :assistant_messages, -> { where(role: 'assistant') }
    scope :tool_messages, -> { where(role: 'tool') }

    # Serialize JSON fields if using databases that don't support JSON natively
    # (PostgreSQL, MySQL 5.7+, and SQLite 3.9+ support JSON natively)
    serialize :tool_calls, coder: JSON if ActiveRecord::VERSION::MAJOR < 7
    serialize :metadata, coder: JSON if ActiveRecord::VERSION::MAJOR < 7

    # Check if this message has tool calls
    def has_tool_calls?
      role == 'assistant' && tool_calls.present? && tool_calls.any?
    end

    # Get parsed tool calls
    def parsed_tool_calls
      return [] unless has_tool_calls?
      tool_calls.is_a?(String) ? JSON.parse(tool_calls) : tool_calls
    end

    # Get parsed content for tool messages
    def parsed_content
      return content unless role == 'tool'
      content.is_a?(String) ? JSON.parse(content) : content
    rescue JSON::ParserError
      content
    end
  end
end
