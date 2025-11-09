class CreateActiveIntelligenceConversations < ActiveRecord::Migration[7.1]
  def change
    create_table :active_intelligence_conversations do |t|
      t.string :agent_class, null: false
      t.string :status, default: 'active', null: false
      t.text :objective
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index :active_intelligence_conversations, :status
    add_index :active_intelligence_conversations, :agent_class
  end
end
