class CreateActiveIntelligenceMessages < ActiveRecord::Migration[7.2]
  def change
    create_table :active_intelligence_messages do |t|
      t.references :conversation, null: false, foreign_key: { to_table: :active_intelligence_conversations }, index: true
      t.string :type, null: false  # For STI (UserMessage, AssistantMessage, ToolMessage)
      t.string :role, null: false  # For API formatting (user, assistant, tool)
      t.text :content

      # Use jsonb for PostgreSQL (more efficient), json for others
      if ActiveRecord::Base.connection.adapter_name.downcase == 'postgresql'
        t.jsonb :tool_calls, default: []
        t.jsonb :metadata, default: {}
      else
        t.json :tool_calls, default: []
        t.json :metadata, default: {}
      end

      t.string :tool_name
      t.string :tool_use_id

      t.timestamps
    end

    add_index :active_intelligence_messages, :type
    add_index :active_intelligence_messages, :role
    add_index :active_intelligence_messages, [:conversation_id, :created_at]
  end
end
