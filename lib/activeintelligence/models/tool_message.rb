module ActiveIntelligence
  class ToolMessage < Message
    validates :tool_name, presence: true
    validates :tool_use_id, presence: true

    # Content can be nil for tool messages (result is stored as JSON)
    # tool_calls should not be set for tool messages
    validate :no_tool_calls

    # Get parsed content
    def parsed_content
      return content unless content.present?
      content.is_a?(String) ? JSON.parse(content) : content
    rescue JSON::ParserError
      content
    end

    private

    def no_tool_calls
      errors.add(:tool_calls, "should not be set for tool messages") if tool_calls.present? && tool_calls.any?
    end
  end
end
