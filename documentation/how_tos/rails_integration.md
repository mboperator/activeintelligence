---
title: Rails Integration
description: Persist conversations to a database using ActiveRecord models, manage conversation lifecycle, and wire agents into Rails controllers.
tags: [rails, active_record, persistence, conversations]
---

## Prerequisites

- Rails 7+ application
- ActiveIntelligence gem installed
- Familiarity with [Memory strategies](../key_concepts/memory)

## 1. Run the Generator

```bash
rails generate active_intelligence:install
rails db:migrate
```

This creates migrations for two tables:

### `active_intelligence_conversations`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint | Primary key |
| `agent_class` | string | `"MyAgent"` — used to reconstruct the agent |
| `status` | string | `"active"` or `"archived"` |
| `agent_state` | string | `"idle"`, `"awaiting_tool_results"`, `"completed"` |
| `user_id` | bigint | Optional foreign key |
| `metadata` | json | Optional custom data |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### `active_intelligence_messages`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint | Primary key |
| `conversation_id` | bigint | Foreign key |
| `type` | string | STI discriminator (`UserMessage`, `AssistantMessage`, `ToolMessage`) |
| `role` | string | `"user"`, `"assistant"`, `"tool"` |
| `content` | text | Message text |
| `tool_calls` | json | Array of tool call hashes (AssistantMessage only) |
| `tool_name` | string | Tool identifier (ToolMessage only) |
| `tool_use_id` | string | Claude's tool use ID (ToolMessage only) |
| `status` | string | `"pending"`, `"complete"`, `"error"` (ToolMessage only) |
| `parameters` | json | Tool input params (ToolMessage only) |
| `created_at` | datetime | |
| `updated_at` | datetime | |

## 2. Configure Agent

```ruby
class SupportAgent < ActiveIntelligence::Agent
  model :claude
  memory :active_record
  identity "You are a customer support agent."
  tool LookupOrderTool
end
```

## 3. Controller Pattern

```ruby
class ConversationsController < ApplicationController
  before_action :authenticate_user!

  # POST /conversations
  def create
    conversation = ActiveIntelligence::Conversation.create!(
      agent_class: "SupportAgent",
      user: current_user
    )
    render json: { id: conversation.id }
  end

  # POST /conversations/:id/messages
  def message
    conversation = current_user.conversations.find(params[:id])
    agent = conversation.agent  # reconstructs SupportAgent with full history

    response = agent.send_message(params[:message])
    render json: { response: response }
  end
end
```

`Conversation#agent` (`models/conversation.rb:15-23`) uses the stored `agent_class` to instantiate the correct subclass with the conversation attached.

## 4. Streaming in Rails

```ruby
class ConversationsController < ApplicationController
  include ActionController::Live

  def stream
    conversation = current_user.conversations.find(params[:id])
    agent = conversation.agent

    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"

    agent.send_message(params[:message], stream: true) do |chunk|
      response.stream.write("data: #{chunk.to_json}\n\n")
    end

  rescue => e
    response.stream.write("data: #{({ error: e.message }).to_json}\n\n")
  ensure
    response.stream.close
  end
end
```

## 5. Conversation Lifecycle

```ruby
# List active conversations for a user
user.conversations.active

# Archive a conversation
conversation.archive!

# Get last message
conversation.last_message

# Count messages
conversation.message_count

# Check agent state
conversation.agent_state  # "idle", "awaiting_tool_results", "completed"
```

Source: `models/conversation.rb`

## 6. Frontend Tool Pattern

When using frontend tools with persisted conversations, state survives across HTTP requests:

```ruby
# Request 1: User sends message
agent = conversation.agent
result = agent.send_message("Please process a file.")
# agent.paused_for_frontend? => true
# Serialize result to client, save conversation

# Request 2: Client returns tool result
agent = conversation.agent  # reload from DB
agent.continue_with_tool_results({
  "tool_use_id" => params[:tool_use_id],
  "result"      => params[:file_contents]
})
```

The agent's `awaiting_tool_results` state is persisted to `conversations.agent_state` between requests.

## 7. User Association

Associate conversations with users by adding the foreign key:

```ruby
# In your User model
has_many :conversations,
  class_name: "ActiveIntelligence::Conversation",
  foreign_key: :user_id

# Create with user
conversation = current_user.conversations.create!(agent_class: "SupportAgent")
```

The `user_id` column is optional — conversations without a user are valid.

## 8. Message Scopes

```ruby
conversation.messages.by_role("user")
conversation.messages.by_role("assistant")

# ToolMessage-specific
conversation.messages.where(type: "ActiveIntelligence::ToolMessage").pending
conversation.messages.where(type: "ActiveIntelligence::ToolMessage").complete
conversation.messages.where(type: "ActiveIntelligence::ToolMessage").with_errors
```

Source: `models/tool_message.rb`, `models/message.rb`
