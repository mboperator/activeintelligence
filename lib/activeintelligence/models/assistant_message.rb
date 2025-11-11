module ActiveIntelligence
  class AssistantMessage < Message
    validates :content, presence: true

    # Ensure tool-specific fields are not set
    validate :no_tool_response_fields

    # Check if this message has tool calls
    def has_tool_calls?
      tool_calls.present? && tool_calls.any?
    end

    # Get parsed tool calls
    def parsed_tool_calls
      return [] unless has_tool_calls?
      tool_calls.is_a?(String) ? JSON.parse(tool_calls) : tool_calls
    end

    private

    def no_tool_response_fields
      errors.add(:tool_name, "should not be set for assistant messages") if tool_name.present?
      errors.add(:tool_use_id, "should not be set for assistant messages") if tool_use_id.present?
    end
  end
end
