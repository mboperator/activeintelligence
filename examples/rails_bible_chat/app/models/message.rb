class Message < ActiveRecord::Base
  self.table_name = 'active_intelligence_messages'

  belongs_to :conversation

  validates :role, presence: true, inclusion: { in: %w[user assistant tool] }
  validates :content, presence: true, if: -> { role != 'tool' }

  scope :by_role, ->(role) { where(role: role) }
  scope :user_messages, -> { where(role: 'user') }
  scope :assistant_messages, -> { where(role: 'assistant') }
  scope :tool_messages, -> { where(role: 'tool') }

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
