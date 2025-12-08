module ActiveIntelligence
  class UserMessage < Message
    SEND_STATUSES = {
      pending: 'pending',
      sent: 'sent',
      failed: 'failed'
    }.freeze

    validates :content, presence: true
    validates :send_status, inclusion: { in: SEND_STATUSES.values }, allow_nil: true

    # Ensure tool-specific fields are not set
    validate :no_tool_fields

    # Send status scopes
    scope :pending, -> { where(send_status: SEND_STATUSES[:pending]) }
    scope :sent, -> { where(send_status: SEND_STATUSES[:sent]) }
    scope :failed, -> { where(send_status: SEND_STATUSES[:failed]) }
    scope :retriable, -> { failed.where('retry_count < ?', 5) }

    # Mark message as successfully sent
    def mark_sent!
      update!(send_status: SEND_STATUSES[:sent], failure_reason: nil)
    end

    # Mark message as failed with reason
    def mark_failed!(reason = nil)
      update!(
        send_status: SEND_STATUSES[:failed],
        failure_reason: reason,
        retry_count: (retry_count || 0) + 1
      )
    end

    # Reset to pending for retry
    def reset_for_retry!
      update!(send_status: SEND_STATUSES[:pending])
    end

    # Status checks
    def pending?
      send_status == SEND_STATUSES[:pending]
    end

    def sent?
      send_status == SEND_STATUSES[:sent] || send_status.nil?
    end

    def failed?
      send_status == SEND_STATUSES[:failed]
    end

    # Check if message can be retried
    def retriable?
      failed? && (retry_count || 0) < 5
    end

    private

    def no_tool_fields
      errors.add(:tool_calls, "should not be set for user messages") if tool_calls.present? && tool_calls.any?
      errors.add(:tool_name, "should not be set for user messages") if tool_name.present?
      errors.add(:tool_use_id, "should not be set for user messages") if tool_use_id.present?
    end
  end
end
