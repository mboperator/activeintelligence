module ActiveIntelligence
  class UserMessage < Message
    validates :content, presence: true

    # Ensure tool-specific fields are not set
    validate :no_tool_fields

    private

    def no_tool_fields
      errors.add(:tool_calls, "should not be set for user messages") if tool_calls.present? && tool_calls.any?
      errors.add(:tool_name, "should not be set for user messages") if tool_name.present?
      errors.add(:tool_use_id, "should not be set for user messages") if tool_use_id.present?
    end
  end
end
