# Debug Panel - Real-time Agent Observability

The Bible Study Chat example now includes a real-time debug panel that displays all observability hooks as they fire during agent execution.

## Features

- **Floating, collapsible panel** in the bottom-right corner
- **Real-time updates** via ActionCable WebSocket
- **Color-coded hooks** for easy visual scanning
- **JSON payload inspection** for each event
- **Ephemeral events** - refreshes on page reload

## Architecture

### Backend (Rails)
1. **ActionCable Setup**
   - `app/channels/application_cable/connection.rb` - WebSocket connection handler
   - `app/channels/debug_channel.rb` - Channel for broadcasting hook events

2. **Agent Hooks**
   - `app/agents/bible_study_agent.rb` - All 16 observability hooks configured
   - Hooks broadcast events to the DebugChannel

### Frontend (React + TypeScript)
1. **DebugPanel Component**
   - `app/frontend/components/DebugPanel.tsx` - Main panel component
   - Connects to ActionCable on mount
   - Auto-scrolls to latest event
   - Collapsible and dismissible

2. **Integration**
   - Added to `app/frontend/pages/Conversations/Show.tsx`
   - Receives events in real-time as user interacts with the chat

## Hooks Displayed

The panel shows all 16 hook types:

### Session Lifecycle (Purple)
- `on_session_start` - Agent initialized
- `on_session_end` - Session explicitly ended

### Turn Lifecycle (Blue)
- `on_turn_start` - User message received
- `on_turn_end` - Turn completed with usage stats

### Response Lifecycle (Green)
- `on_response_start` - API call begins
- `on_response_end` - API call completes with usage
- `on_response_chunk` - Streaming chunk received

### Thinking (Pink)
- `on_thinking_start` - Extended thinking begins
- `on_thinking_end` - Thinking completes with content

### Tool Execution (Orange)
- `on_tool_start` - Tool begins execution
- `on_tool_end` - Tool completes successfully
- `on_tool_error` - Tool encounters error

### Other Events
- `on_message_added` (Indigo) - Message added to history
- `on_iteration` (Yellow) - Tool loop iteration
- `on_error` (Red) - Agent-level error
- `on_stop` (Gray) - Execution stops

## Setup

### 1. Install Dependencies
```bash
npm install
```

This will install `@rails/actioncable` for WebSocket support.

### 2. Start Rails Server
```bash
bin/rails server
```

ActionCable runs on the same port as the Rails server.

### 3. Navigate to a Conversation
Open http://localhost:3000/conversations and start a new chat.

The debug panel will appear in the bottom-right corner and start showing events immediately.

## Usage

### Panel Controls
- **Collapse/Expand**: Click the chevron icon
- **Clear Events**: Click the trash icon
- **Hide Panel**: Click the X icon (can be re-shown with "Show Debug Panel" button)

### Event Inspection
Each event displays:
- **Hook name** (color-coded)
- **Timestamp** (local time)
- **Full JSON payload** with proper formatting

### Example Event Flow

When you send a message like "Tell me about John 3:16":

```
[on_turn_start] User message received
[on_message_added] UserMessage added
[on_response_start] API call begins
[on_response_chunk] Text streaming...
[on_tool_start] bible_lookup tool called
[on_tool_end] bible_lookup returns data
[on_message_added] ToolResponse added
[on_response_start] API call with tool result
[on_response_chunk] Final response streaming...
[on_response_end] API complete (with usage stats)
[on_turn_end] Turn complete (total tokens used)
[on_stop] Execution complete
```

## Implementation Notes

### Broadcast Safety
The `broadcast_hook` method includes error handling to prevent broadcasting failures from breaking the agent:

```ruby
rescue => e
  Rails.logger.error "Failed to broadcast hook #{hook_name}: #{e.message}"
end
```

### Performance
- Events are ephemeral (not persisted)
- Panel auto-scrolls to latest event
- Old events are kept in state until page reload or manual clear

### Development Tips
- Use the panel to understand agent execution flow
- Inspect usage data to optimize token consumption
- Monitor tool execution timing
- Debug frontend vs backend tool routing

## Future Enhancements
- Persistent event storage
- Event filtering by hook type
- Export events to JSON
- Performance metrics dashboard
- Token cost calculator
