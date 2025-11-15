# Hybrid Frontend/Backend Tool Execution - Implementation Summary

## Overview

This implementation adds support for **hybrid tool execution** in ActiveIntelligence, allowing agents to use both backend tools (executed on the server) and frontend tools (executed in the browser), while maintaining a single, continuous conversation thread with Claude.

## What Was Implemented

### 1. Tool Execution Context DSL (`lib/activeintelligence/tool.rb`)

**Changes:**
- Added `@execution_context` instance variable (defaults to `:backend`)
- Added `execution_context(context)` DSL method
- Added `frontend?` and `backend?` helper methods

**Usage:**
```ruby
class MyFrontendTool < ActiveIntelligence::Tool
  execution_context :frontend  # This tool runs in the browser

  name "file_picker"
  description "Let the user pick a file"

  def execute(params)
    # This method won't actually run on backend
    # Agent will pause and return this to React
    success_response({ action: :file_picker })
  end
end
```

### 2. Agent State Management (`lib/activeintelligence/agent.rb`)

**Changes:**
- Added `STATES` constant (idle, awaiting_tool_results, completed)
- Added `@state` instance variable
- Updated `initialize` to load state from conversation
- Modified `send_message` to handle frontend tool pauses
- Added `continue_with_tool_results` method for resuming
- Updated `process_tool_calls` to create ALL tool responses optimistically with status
- Updated `process_tool_calls_streaming` to create ALL tool responses optimistically with status
- Added helper methods:
  - `partition_tool_calls` - Separates frontend/backend tools
  - `find_tool` - Finds tool by name
  - `has_pending_tools?` - Checks if any tool responses are pending
  - `pending_tools` - Returns all pending tool responses
  - `find_pending_tool_response` - Finds pending tool response by tool_use_id
  - `find_tool_response` - Finds any tool response by tool_use_id
  - `load_state_from_conversation` - Restores state from DB
  - `update_state` - Persists state to DB
  - `persist_agent_class` - Saves agent class name for reconstruction
  - `paused_for_frontend?` - Checks if paused
  - `build_pending_tools_response` - Formats response with pending tools for frontend

**Flow:**
```ruby
# Initial message
response = agent.send_message("Show me an emoji")
# => { status: :awaiting_tool_results, pending_tools: [...], conversation_id: 123 }

# React executes the tool and sends result back
tool_results = [{
  tool_use_id: "toolu_abc123",
  result: { success: true, data: { emoji: "🙏", displayed: true } }
}]

final_response = agent.continue_with_tool_results(tool_results)
# => "I've displayed the praying hands emoji for you..."
```

**Key Architecture:**
- ALL tool responses are created as "pending" when Claude requests them
- Backend tools execute immediately and mark status as "complete"
- Frontend tools stay "pending" until browser executes them
- Agent only calls Claude when ALL tool responses are complete
- Message history with status is single source of truth

### 3. Database Schema (`examples/rails_bible_chat/db/migrate/...`)

**Migrations:**
1. `20251115000001_add_agent_state_to_conversations.rb`
2. `20251115000002_add_status_and_parameters_to_messages.rb`

**New columns on `active_intelligence_conversations`:**
- `agent_state` (string, default: 'idle') - Current execution state
- `agent_class_name` (string) - Agent class for reconstruction

**New columns on `active_intelligence_messages`:**
- `status` (string, default: 'complete') - Message status (pending, complete, error)
- `parameters` (json) - Tool parameters (denormalized for frontend convenience)

**Indexes:**
- `[:conversation_id, :status]` - For querying pending tools
- `[:conversation_id, :type, :status]` - For filtering by message type and status

### 4. Example Frontend Tool (`examples/rails_bible_chat/app/tools/show_emoji_tool.rb`)

A simple demo tool that displays emojis in the chat interface:

```ruby
class ShowEmojiTool < ActiveIntelligence::Tool
  execution_context :frontend

  name "show_emoji"
  description "Display an emoji or emoticon to the user"

  param :emoji, type: String, required: true
  param :size, type: String, default: "large", enum: ["small", "medium", "large"]
  param :message, type: String, required: false

  def execute(params)
    success_response({
      emoji: params[:emoji],
      size: params[:size],
      message: params[:message]
    })
  end
end
```

### 5. Updated Bible Study Agent

**File:** `examples/rails_bible_chat/app/agents/bible_study_agent.rb`

- Registered `ShowEmojiTool`
- Updated identity to encourage emoji usage

### 6. Updated Controller (`examples/rails_bible_chat/app/controllers/conversations_controller.rb`)

**Changes to `send_message` method (static mode):**
- Checks for `tool_results` param (resuming)
- Calls `continue_with_tool_results` when resuming
- Returns different JSON based on response type:
  - `type: 'frontend_tool_request'` with `pending_tools` when paused
  - `type: 'completed'` when done

**Changes to `send_message_streaming` method (streaming mode):**
- Checks for `tool_results` param (resuming)
- Calls `continue_with_tool_results(stream: true)` when resuming
- Emits SSE event `frontend_tool_request` with `pending_tools` when frontend tool is needed
- Pending tools include `tool_use_id`, `tool_name`, `parameters`, and optionally `message_id`
- Closes stream after emitting event
- Frontend resumes by making new POST with tool results

### 7. Documentation & Examples

**Created:**
- `FRONTEND_TOOL_EXAMPLE.md` - Complete React integration guide
- `examples/test_frontend_tools.rb` - Unit tests for tool DSL
- `HYBRID_TOOLS_IMPLEMENTATION.md` (this file)

## How It Works

### Execution Flow (Static Mode)

```
1. User sends message via POST
   ↓
2. Agent sends message to Claude
   ↓
3. Claude responds with tool calls
   ↓
4. Agent creates ALL tool responses as "pending" (optimistic)
   ↓
5. Agent partitions tools into frontend/backend
   ↓
6. Backend tools → Execute and mark "complete"
   ↓
7. Check for pending tools
   ↓
8a. If pending tools exist → Pause & return JSON response
8b. If no pending tools → Call Claude with ALL completed tool results
   ↓
9. React executes frontend tool
   ↓
10. React sends result back via POST with tool_results
    ↓
11. Agent calls continue_with_tool_results()
    ↓
12. Agent marks frontend tool response as "complete"
    ↓
13. Check for pending tools again
    ↓
14a. If still pending → Return pending tools response
14b. If all complete → Call Claude with ALL tool results
    ↓
15. Back to step 3 (loop until complete)
```

### Execution Flow (Streaming Mode)

```
1. User sends message via GET/POST (SSE stream opens)
   ↓
2. Agent sends message to Claude
   ↓
3. Claude responds with tool calls (streaming)
   ↓
4. Agent creates ALL tool responses as "pending" (optimistic)
   ↓
5. Agent partitions tools into frontend/backend
   ↓
6. Backend tools → Execute and mark "complete" → Stream results to React
   ↓
7. Check for pending tools
   ↓
8a. If pending tools → Emit SSE event 'frontend_tool_request' → Stream closes
8b. If no pending → Call Claude with ALL tool results (streaming)
   ↓
9. React executes frontend tool
   ↓
10. React sends result back via POST with tool_results (new stream opens)
    ↓
11. Agent calls continue_with_tool_results(stream: true)
    ↓
12. Agent marks frontend tool response as "complete"
    ↓
13. Agent streams the completed tool result
    ↓
14. Check for pending tools again
    ↓
15a. If still pending → Emit SSE event → Stream closes
15b. If all complete → Call Claude with ALL tool results (streaming)
    ↓
16. Back to step 3 (loop until complete)
```

### Multi-User Support

**State Persistence:**
- All state stored in `conversations` table
- Each conversation isolated by user
- Agent can be reconstructed from DB on any server
- Survives server restarts and deploys

**Stateless Between Requests:**
- No in-memory state required
- Load balancer can route to any server
- Perfect for multi-user, multi-server environments

## Testing

### Unit Tests

Run the RSpec test suite:
```bash
rake spec
# Or specifically:
rspec spec/activeintelligence/tool_spec.rb
rspec spec/activeintelligence/agent_hybrid_tools_spec.rb
```

**Test Coverage:**
- `spec/activeintelligence/tool_spec.rb` (14 examples)
  - execution_context DSL (:frontend, :backend, default)
  - frontend? and backend? helper methods
  - JSON schema generation
  - Tool execution
  - Parameter validation

- `spec/activeintelligence/agent_hybrid_tools_spec.rb` (18 examples)
  - Agent state management (idle, awaiting_tool_results, completed)
  - partition_tool_calls logic
  - find_tool method
  - has_pending_tools? and pending_tools methods
  - continue_with_tool_results
  - build_pending_tools_response

### Demo Script

Run the demo to see output:
```bash
ruby examples/demo_frontend_tools.rb
```

This is NOT a test suite - it just demonstrates the functionality by printing output.

### Integration Testing

Requires:
1. Rails app with database
2. ANTHROPIC_API_KEY environment variable
3. React frontend implementation

See `FRONTEND_TOOL_EXAMPLE.md` for full integration guide.

## Example Usage in Rails Console

```ruby
# Create conversation
conversation = ActiveIntelligence::Conversation.create!(
  agent_class: 'BibleStudyAgent',
  objective: 'Bible study'
)

# Create agent
agent = BibleStudyAgent.new(conversation: conversation)

# Send message that triggers frontend tool
response = agent.send_message("Show me a praying hands emoji")

# Check response
puts response[:status]        # => :awaiting_tool_results
puts response[:pending_tools] # => [{ tool_use_id: "toolu_...", tool_name: "show_emoji", parameters: {...} }]

# Simulate frontend execution
tool_results = [{
  tool_use_id: response[:pending_tools].first[:tool_use_id],
  result: {
    success: true,
    data: { emoji: "🙏", size: "large", displayed: true }
  }
}]

# Continue conversation
final_response = agent.continue_with_tool_results(tool_results)
puts final_response  # => "I've displayed the praying hands emoji..."

# Check state
puts agent.state  # => "completed"

# Check message history - all tool responses are in there with status
puts agent.messages.last.class  # => ActiveIntelligence::Messages::ToolResponse
puts agent.messages.last.status # => "complete"
```

## Key Benefits

✅ **Single Conversation Thread**
- Frontend tool results sent back to same conversation
- Claude maintains full context across frontend/backend boundaries
- No splitting or merging of conversation threads

✅ **Multi-User Safe**
- All state persisted in database
- Conversations isolated by user
- Concurrent users don't interfere

✅ **Scalable**
- Stateless between requests
- Works across multiple Rails servers
- Survives deploys and restarts

✅ **Flexible**
- Easy to add new frontend tools
- Tools self-describe their execution context
- Backend tools continue to work unchanged

✅ **Developer Friendly**
- Simple DSL: `execution_context :frontend`
- Clear pause/resume pattern
- Comprehensive error handling

## Future Enhancements

### Possible Improvements

1. **Tool Timeout Handling**
   - Add timeout for frontend tool execution
   - Auto-fail if user doesn't respond

2. **Tool Permission System**
   - Ask user to approve frontend tools
   - Remember permissions per tool

3. **Tool Analytics**
   - Track tool usage metrics
   - Monitor frontend tool performance

4. **Parallel Tool Execution**
   - Currently backend tools execute sequentially
   - Could execute multiple backend tools in parallel

### Completed Enhancements

✅ **Streaming Support** (Completed)
   - Full streaming mode support for frontend tools
   - SSE events for frontend tool requests

✅ **Mixed Tool Calls** (Completed)
   - Backend tools execute immediately
   - Frontend tools pause only after backend tools complete
   - All tool responses created optimistically with status tracking

## Files Modified

**Core Library:**
- `lib/activeintelligence/tool.rb` (+30 lines)
- `lib/activeintelligence/agent.rb` (+150 lines)

**Rails Example:**
- `examples/rails_bible_chat/db/migrate/20251115000001_add_agent_state_to_conversations.rb` (new)
- `examples/rails_bible_chat/app/tools/show_emoji_tool.rb` (new)
- `examples/rails_bible_chat/app/agents/bible_study_agent.rb` (+2 lines)
- `examples/rails_bible_chat/app/controllers/conversations_controller.rb` (+20 lines)

**Documentation:**
- `FRONTEND_TOOL_EXAMPLE.md` (new)
- `HYBRID_TOOLS_IMPLEMENTATION.md` (new)
- `examples/test_frontend_tools.rb` (new)

## Migration Instructions

### For Existing Apps

1. **Run migrations:**
   ```bash
   # Migration 1: Add agent state tracking
   rails generate migration AddAgentStateToConversations
   # Copy content from:
   # examples/rails_bible_chat/db/migrate/20251115000001_add_agent_state_to_conversations.rb

   # Migration 2: Add status and parameters to messages
   rails generate migration AddStatusAndParametersToMessages
   # Copy content from:
   # examples/rails_bible_chat/db/migrate/20251115000002_add_status_and_parameters_to_messages.rb

   rails db:migrate
   ```

2. **Update gem:**
   ```bash
   bundle update activeintelligence
   ```

3. **Update controller:**
   - Add tool_results handling to send_message action
   - Update response check from `status: :awaiting_frontend_tool` to `status: :awaiting_tool_results`
   - Update response key from `tools:` to `pending_tools:`

4. **Update frontend:**
   - Add frontend tool handler for SSE event `frontend_tool_request`
   - Extract `pending_tools` from event data
   - Implement tool-specific UI components
   - Send results back with `tool_use_id` and `result` (optionally `message_id`)

See `FRONTEND_TOOL_EXAMPLE.md` for complete integration guide.

## Questions & Support

For questions or issues with hybrid tool execution:
1. Check `FRONTEND_TOOL_EXAMPLE.md` for integration details
2. Review `examples/test_frontend_tools.rb` for examples
3. Open an issue on GitHub

---

**Implementation Date:** November 15, 2025
**Version:** ActiveIntelligence 0.0.1
**Author:** Claude Code (with guidance from Marcus Bernales)
