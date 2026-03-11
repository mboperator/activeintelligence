---
title: Memory
description: How conversation history is stored — in-memory for simple use cases or ActiveRecord-backed for persistent, database-driven conversations.
tags: [memory, persistence, active_record, conversation]
---

## Overview

Memory determines where an agent's conversation history lives. Choose a strategy with the `memory` DSL method:

```ruby
class MyAgent < ActiveIntelligence::Agent
  memory :in_memory     # default
  # or
  memory :active_record # persistent, Rails only
end
```

Both strategies expose the same interface — the agent reads and writes `@messages` the same way regardless of which strategy is active.

## In-Memory Strategy

The default. History is stored in a plain Ruby array on the agent instance. It exists for the lifetime of the object and disappears when the object is garbage collected.

**Use when:**
- Building CLI tools or scripts
- Each request is stateless (API endpoints where you reconstruct context each call)
- Testing and development

```ruby
agent = MyAgent.new  # fresh conversation every time
agent.send_message("Hello")
agent.send_message("Remember that?")  # context preserved within this instance
```

**Limitation:** Two separate `MyAgent.new` calls share no history. Persistence across HTTP requests requires a different approach — either pass messages in explicitly or use ActiveRecord.

## ActiveRecord Strategy

Backs the conversation with a `Conversation` record and `Message` STI models in your Rails database. History survives process restarts, scales horizontally, and works naturally with Rails.

```ruby
class MyAgent < ActiveIntelligence::Agent
  memory :active_record
end

# Create a new conversation
conv = ActiveIntelligence::Conversation.create!(agent_class: "MyAgent")
agent = MyAgent.new(conversation: conv)
agent.send_message("Start of a persistent conversation")

# Resume later (different process, different request)
conv = ActiveIntelligence::Conversation.find(id)
agent = conv.agent  # reconstructs MyAgent with full history
agent.send_message("Continuing where we left off")
```

**How it works:**
- `load_messages_from_db` (`agent.rb:764-788`) reads all messages for the conversation on init
- `persist_message_to_db` (`agent.rb:790-820`) writes each new message as it's added to history
- Agent state (idle / awaiting_tool_results / completed) is stored on the `Conversation` record
- The agent class name is persisted so `Conversation#agent` can reconstruct the right subclass

### Database Models

```mermaid
erDiagram
    Conversation {
        string agent_class
        string status
        string agent_state
        belongs_to user optional
    }
    Message {
        string type
        string role
        text content
        json tool_calls
        string tool_name
        string tool_use_id
        string status
        json parameters
        belongs_to conversation
    }

    Conversation ||--o{ Message : has_many
```

| Model | Inherits From | Role |
|-------|--------------|------|
| `ActiveIntelligence::Message` | `ActiveRecord::Base` | STI base |
| `ActiveIntelligence::UserMessage` | `Message` | User turns |
| `ActiveIntelligence::AssistantMessage` | `Message` | Claude responses |
| `ActiveIntelligence::ToolMessage` | `Message` | Tool results |
| `ActiveIntelligence::Conversation` | `ActiveRecord::Base` | Owns messages |

See [Rails Integration](../how_tos/rails_integration) for migration and setup details.

## Adding New Memory Strategies

The memory strategy is resolved in the agent initializer. To add a strategy (e.g., Redis-backed):

1. Add a new symbol condition in the `initialize` method (`agent.rb:51-75`)
2. Implement a backing store that populates `@messages` on init
3. Override the message persistence hook to write to your store

The agent itself only reads and writes `@messages` — all persistence logic lives in the strategy-specific code.
