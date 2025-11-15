class AddAgentStateToConversations < ActiveRecord::Migration[7.2]
  def change
    add_column :active_intelligence_conversations, :agent_state, :string, default: 'idle'
    add_column :active_intelligence_conversations, :agent_class_name, :string

    add_index :active_intelligence_conversations, :agent_state
  end
end
