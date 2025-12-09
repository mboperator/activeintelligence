class AddRateLimitingColumnsToMessages < ActiveRecord::Migration[7.2]
  def change
    # User message send status tracking (for rate limiting/retry)
    add_column :active_intelligence_messages, :send_status, :string, default: 'sent'
    add_column :active_intelligence_messages, :failure_reason, :text
    add_column :active_intelligence_messages, :retry_count, :integer, default: 0

    # Index for querying failed/retriable messages
    add_index :active_intelligence_messages, [:conversation_id, :send_status]

    # Backfill existing user messages as 'sent' (they were successfully sent)
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE active_intelligence_messages
          SET send_status = 'sent'
          WHERE type = 'ActiveIntelligence::UserMessage'
            AND send_status IS NULL
        SQL
      end
    end
  end
end
