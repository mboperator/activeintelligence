class AddStatusAndParametersToMessages < ActiveRecord::Migration[7.2]
  def change
    # Add status column (pending, complete, error)
    add_column :active_intelligence_messages, :status, :string, default: 'complete'

    # Add parameters column (denormalized for convenience)
    add_column :active_intelligence_messages, :parameters, :json

    # Add indexes for querying pending tools
    add_index :active_intelligence_messages, [:conversation_id, :status]
    add_index :active_intelligence_messages, [:conversation_id, :type, :status]

    # Backfill existing messages (all existing tool messages are complete)
    reversible do |dir|
      dir.up do
        ActiveIntelligence::Message.update_all(status: 'complete')
      end
    end
  end
end
