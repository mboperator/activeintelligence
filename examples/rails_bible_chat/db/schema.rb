# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2025_11_15_000002) do
  create_table "active_intelligence_conversations", force: :cascade do |t|
    t.integer "user_id"
    t.string "agent_class", null: false
    t.string "status", default: "active", null: false
    t.text "objective"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "agent_state", default: "idle"
    t.string "agent_class_name"
    t.index ["agent_class"], name: "index_active_intelligence_conversations_on_agent_class"
    t.index ["agent_state"], name: "index_active_intelligence_conversations_on_agent_state"
    t.index ["status"], name: "index_active_intelligence_conversations_on_status"
    t.index ["user_id"], name: "index_active_intelligence_conversations_on_user_id"
  end

  create_table "active_intelligence_messages", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.string "type", null: false
    t.string "role", null: false
    t.text "content"
    t.json "tool_calls", default: []
    t.json "metadata", default: {}
    t.string "tool_name"
    t.string "tool_use_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "complete"
    t.json "parameters"
    t.index ["conversation_id", "created_at"], name: "idx_on_conversation_id_created_at_366fbcff9e"
    t.index ["conversation_id", "status"], name: "idx_on_conversation_id_status_981a294b68"
    t.index ["conversation_id", "type", "status"], name: "idx_on_conversation_id_type_status_a849d374cb"
    t.index ["conversation_id"], name: "index_active_intelligence_messages_on_conversation_id"
    t.index ["role"], name: "index_active_intelligence_messages_on_role"
    t.index ["type"], name: "index_active_intelligence_messages_on_type"
  end

  add_foreign_key "active_intelligence_messages", "active_intelligence_conversations", column: "conversation_id"
end
