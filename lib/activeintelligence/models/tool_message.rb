module ActiveIntelligence
  class ToolMessage < Message
    validates :tool_name, presence: true
    validates :tool_use_id, presence: true
    validates :status, inclusion: { in: %w[pending complete error] }

    # Content can be nil for tool messages (result is stored as JSON)
    # tool_calls should not be set for tool messages
    validate :no_tool_calls

    # Scopes
    scope :pending, -> { where(status: 'pending') }
    scope :complete, -> { where(status: 'complete') }
    scope :with_errors, -> { where(status: 'error') }

    # Status checks
    def pending?
      status == 'pending'
    end

    def complete?
      status == 'complete'
    end

    def error?
      status == 'error'
    end

    # Complete this tool response
    def complete!(result)
      is_error = result.is_a?(Hash) && result[:error] == true

      update!(
        status: is_error ? 'error' : 'complete',
        content: result.to_json
      )
    end

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
