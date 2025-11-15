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
- Added `STATES` constant (idle, awaiting_frontend_tool, completed)
- Added `@state` instance variable
- Updated `initialize` to load state from conversation
- Modified `send_message` to handle frontend tool pauses
- Added `continue_with_tool_results` method for resuming
- Updated `process_tool_calls` to pause when frontend tools detected
- Added helper methods:
  - `partition_tool_calls` - Separates frontend/backend tools
  - `find_tool` - Finds tool by name
  - `load_state_from_conversation` - Restores state from DB
  - `update_state` - Persists state to DB
  - `persist_agent_class` - Saves agent class name for reconstruction
  - `paused_for_frontend?` - Checks if paused
  - `store_pending_frontend_tools` - Saves tools waiting for frontend
  - `clear_pending_frontend_tools` - Clears pending tools
  - `build_frontend_response` - Formats response for frontend

**Flow:**
```ruby
# Initial message
response = agent.send_message("Show me an emoji")
# => { status: :awaiting_frontend_tool, tools: [...], conversation_id: 123 }

# React executes the tool and sends result back
tool_results = [{
  tool_use_id: "toolu_abc123",
  tool_name: "show_emoji",
  result: { success: true, data: { emoji: "🙏", displayed: true } }
}]

final_response = agent.continue_with_tool_results(tool_results)
# => "I've displayed the praying hands emoji for you..."
```

### 3. Database Schema (`examples/rails_bible_chat/db/migrate/...`)

**Migration:** `20251115000001_add_agent_state_to_conversations.rb`

**New columns on `active_intelligence_conversations`:**
- `agent_state` (string, default: 'idle') - Current execution state
- `agent_class_name` (string) - Agent class for reconstruction
- `pending_frontend_tools` (json) - Tool calls waiting for frontend execution

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

**Changes to `send_message` method:**
- Checks for `tool_results` param (resuming)
- Calls `continue_with_tool_results` when resuming
- Returns different JSON based on response type:
  - `type: 'frontend_tool_request'` when paused
  - `type: 'completed'` when done

### 7. Documentation & Examples

**Created:**
- `FRONTEND_TOOL_EXAMPLE.md` - Complete React integration guide
- `examples/test_frontend_tools.rb` - Unit tests for tool DSL
- `HYBRID_TOOLS_IMPLEMENTATION.md` (this file)

## How It Works

### Execution Flow

```
1. User sends message
   ↓
2. Agent sends message to Claude
   ↓
3. Claude responds with tool calls
   ↓
4. Agent partitions tools into frontend/backend
   ↓
5a. Backend tools → Execute immediately → Continue loop
5b. Frontend tools → Pause & return to React
   ↓
6. React executes frontend tool
   ↓
7. React sends result back to Rails
   ↓
8. Agent calls continue_with_tool_results()
   ↓
9. Tool result added to conversation
   ↓
10. Agent calls Claude with tool result
    ↓
11. Back to step 3 (loop until complete)
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

Run the test script:
```bash
ruby examples/test_frontend_tools.rb
```

**Tests:**
1. Tool execution context detection
2. JSON schema generation
3. Backend tool execution
4. Frontend tool execution

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
puts response[:status]  # => :awaiting_frontend_tool
puts response[:tools]   # => [{ id: "toolu_...", name: "show_emoji", ... }]

# Simulate frontend execution
tool_results = [{
  tool_use_id: response[:tools].first[:id],
  tool_name: "show_emoji",
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

1. **Streaming Support**
   - Currently only works with static responses
   - Could extend to streaming mode

2. **Mixed Tool Calls**
   - Currently pauses if ANY frontend tool in response
   - Could execute backend tools first, then pause for frontend

3. **Tool Timeout Handling**
   - Add timeout for frontend tool execution
   - Auto-fail if user doesn't respond

4. **Tool Permission System**
   - Ask user to approve frontend tools
   - Remember permissions per tool

5. **Tool Analytics**
   - Track tool usage metrics
   - Monitor frontend tool performance

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

1. **Run migration:**
   ```bash
   rails generate migration AddAgentStateToConversations
   # Copy content from examples/rails_bible_chat/db/migrate/20251115000001_add_agent_state_to_conversations.rb
   rails db:migrate
   ```

2. **Update gem:**
   ```bash
   bundle update activeintelligence
   ```

3. **Update controller:**
   - Add tool_results handling to send_message action
   - Check response type before rendering

4. **Update frontend:**
   - Add frontend tool handler
   - Implement tool-specific UI components
   - Send results back to Rails

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
