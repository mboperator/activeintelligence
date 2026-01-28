# Bible Study Chat - ActiveIntelligence Rails Example

A complete example Rails application demonstrating ActiveIntelligence with database-backed conversation persistence, custom tools, and streaming responses.

## Features

- 📖 **Bible Study Agent** - Knowledgeable AI assistant for Bible exploration
- 🔍 **Bible Reference Tool** - Automatically looks up verses using bible-api.com
- 💬 **Persistent Conversations** - Database-backed message history
- ⚡ **Real-time Streaming** - SSE streaming for instant responses
- 🎨 **Clean UI** - Simple, responsive chat interface
- 🔌 **MCP Server** - Expose tools via Model Context Protocol for use with Claude Desktop and other AI apps

## What This Demonstrates

This example shows you how to:

1. **Integrate ActiveIntelligence into Rails** with the `:active_record` memory strategy
2. **Create custom tools** that agents can use (BibleReferenceTool)
3. **Build conversational agents** with specific expertise (BibleStudyAgent)
4. **Implement streaming responses** using ActionController::Live
5. **Persist conversations** to a database for multi-session use
6. **Build a chat UI** that works with streaming responses

## Project Structure

```
rails_bible_chat/
├── app/
│   ├── agents/
│   │   └── bible_study_agent.rb        # The AI agent with Bible expertise
│   ├── tools/
│   │   └── bible_reference_tool.rb     # Tool for looking up Bible verses
│   ├── models/
│   │   └── active_intelligence/
│   │       ├── conversation.rb         # Conversation persistence model
│   │       └── message.rb              # Message persistence model
│   ├── controllers/
│   │   └── conversations_controller.rb # Chat API & streaming endpoints
│   └── views/
│       └── conversations/
│           ├── index.html.erb          # Conversation list
│           └── show.html.erb           # Chat interface
├── config/
│   ├── routes.rb                       # Routes configuration
│   ├── database.yml                    # SQLite database config
│   └── initializers/
│       └── active_intelligence.rb      # ActiveIntelligence config
└── db/
    └── migrate/
        ├── *_create_active_intelligence_conversations.rb
        └── *_create_active_intelligence_messages.rb
```

## Prerequisites

- Ruby 2.6+
- Bundler
- SQLite3
- An Anthropic API key

## Setup

### 1. Install Dependencies

```bash
cd examples/rails_bible_chat
bundle install
```

### 2. Set Environment Variables

```bash
export ANTHROPIC_API_KEY="sk-ant-your-key-here"
```

Or create a `.env` file:

```bash
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

### 3. Setup Database

```bash
# Create database
bundle exec rails db:create

# Run migrations
bundle exec rails db:migrate
```

### 4. Start the Server

```bash
bundle exec rails server
```

Visit http://localhost:3000

## Usage

### Starting a Conversation

1. Click "Start New Bible Study Conversation" on the homepage
2. You'll be taken to a new chat interface
3. Start asking questions!

### Example Questions

Try asking the agent:

- "Can you show me John 3:16?"
- "What does Psalm 23 say?"
- "Show me Matthew 5:1-12"
- "What is the context of Romans 8:28?"
- "Tell me about the Sermon on the Mount"

### How It Works

1. **User sends a message** → Saved to database as UserMessage
2. **Agent processes message** → May decide to use the bible_lookup tool
3. **If tool is needed**:
   - Agent calls BibleReferenceTool
   - Tool fetches verse from bible-api.com
   - Result saved as ToolResponse
   - Agent continues with the verse text
4. **Agent responds** → Saved as AgentResponse
5. **Conversation persists** → Can be resumed later

## Code Walkthrough

### The Agent (app/agents/bible_study_agent.rb)

```ruby
class BibleStudyAgent < ActiveIntelligence::Agent
  model :claude
  memory :active_record  # Enable database persistence

  identity <<~IDENTITY
    You are a knowledgeable and friendly Bible study assistant...
  IDENTITY

  tool BibleReferenceTool  # Register the Bible lookup tool
end
```

**Key Points:**
- `memory :active_record` enables database-backed conversations
- `identity` sets the agent's personality and instructions
- `tool BibleReferenceTool` gives the agent the ability to look up verses

### The Tool (app/tools/bible_reference_tool.rb)

```ruby
class BibleReferenceTool < ActiveIntelligence::Tool
  name "bible_lookup"
  description "Look up Bible verses by reference"

  param :reference,
        type: String,
        required: true,
        description: "The Bible reference (e.g., 'John 3:16')"

  def execute(params)
    # Fetch from bible-api.com
    result = fetch_bible_verse(params[:reference])

    if result[:success]
      success_response(result)
    else
      error_response("Could not find reference", details: result)
    end
  end
end
```

**Key Points:**
- Tools inherit from `ActiveIntelligence::Tool`
- Use DSL to define name, description, and parameters
- Claude sees the schema and decides when to call the tool
- Must return `success_response()` or `error_response()`

### The Controller (app/controllers/conversations_controller.rb)

```ruby
class ConversationsController < ApplicationController
  include ActionController::Live  # Enable streaming

  def send_message_streaming
    @conversation = ActiveIntelligence::Conversation.find(params[:id])
    agent = @conversation.agent  # Load agent with conversation history

    response.headers['Content-Type'] = 'text/event-stream'

    agent.send_message(params[:message], stream: true) do |chunk|
      response.stream.write "data: #{chunk}\n\n"
    end

    response.stream.write "data: [DONE]\n\n"
  ensure
    response.stream.close
  end
end
```

**Key Points:**
- `@conversation.agent` automatically loads message history from DB
- `stream: true` enables real-time streaming
- Uses Server-Sent Events (SSE) format
- Chunks are yielded as they arrive from Claude

### The Frontend (app/views/conversations/show.html.erb)

```javascript
// Streaming with EventSource API
const response = await fetch(`/conversations/${id}/send_message_streaming`, {
  method: 'POST',
  headers: { 'Accept': 'text/event-stream' }
});

const reader = response.body.getReader();
const decoder = new TextDecoder();

while (true) {
  const { done, value } = await reader.read();
  if (done) break;

  // Append chunks to UI as they arrive
  const chunk = decoder.decode(value);
  assistantContent.textContent += chunk;
}
```

**Key Points:**
- Uses Fetch API with ReadableStream for streaming
- Decodes SSE format (`data: ` prefix)
- Updates UI in real-time as chunks arrive

## Database Schema

### Conversations Table

```sql
CREATE TABLE active_intelligence_conversations (
  id INTEGER PRIMARY KEY,
  agent_class VARCHAR NOT NULL,        -- Which agent class to use
  status VARCHAR DEFAULT 'active',     -- active/archived
  objective TEXT,                      -- Agent's objective
  metadata JSON DEFAULT '{}',          -- Custom data
  created_at DATETIME,
  updated_at DATETIME
);
```

### Messages Table

```sql
CREATE TABLE active_intelligence_messages (
  id INTEGER PRIMARY KEY,
  conversation_id INTEGER NOT NULL,    -- Foreign key to conversations
  role VARCHAR NOT NULL,               -- user/assistant/tool
  content TEXT,                        -- Message content
  tool_calls JSON DEFAULT '[]',        -- Tool calls (for assistant)
  tool_name VARCHAR,                   -- Tool name (for tool messages)
  metadata JSON DEFAULT '{}',          -- Custom data
  created_at DATETIME,
  updated_at DATETIME
);
```

## API Endpoints

### GET /conversations
List recent conversations

### POST /conversations
Create a new conversation

**Response:**
```json
{
  "id": 123,
  "agent_class": "BibleStudyAgent",
  "created_at": "2024-01-01T12:00:00Z"
}
```

### GET /conversations/:id
Get conversation details with message history

**Response:**
```json
{
  "conversation": {
    "id": 123,
    "agent_class": "BibleStudyAgent",
    "status": "active"
  },
  "messages": [
    {
      "id": 1,
      "role": "user",
      "content": "Show me John 3:16",
      "created_at": "..."
    },
    {
      "id": 2,
      "role": "assistant",
      "content": "Let me look that up for you...",
      "created_at": "..."
    }
  ]
}
```

### POST /conversations/:id/send_message
Send a message (non-streaming)

**Request:**
```json
{
  "message": "What does Psalm 23 say?"
}
```

**Response:**
```json
{
  "response": "Let me look up Psalm 23 for you...",
  "message_count": 5
}
```

### POST /conversations/:id/send_message_streaming
Send a message with streaming response

**Request:**
```json
{
  "message": "Tell me about John 3:16"
}
```

**Response:** (Server-Sent Events)
```
data: Let
data:  me
data:  look
data:  that
data:  up
data:  for
data:  you
data: ...
data: [DONE]
```

### POST /mcp
Model Context Protocol endpoint for AI applications

See [MCP Server](#mcp-server-model-context-protocol) section below for details.

## MCP Server (Model Context Protocol)

This app includes an MCP server that exposes the Bible Reference Tool to AI applications like Claude Desktop.

### What is MCP?

The [Model Context Protocol](https://modelcontextprotocol.io) is an open standard for connecting AI applications to external tools and data sources. With MCP, you can use the same tools from:
- Claude Desktop
- Other MCP-compatible AI applications
- Custom integrations

### Testing the MCP Server

Once the Rails server is running, you can test the MCP endpoint with curl:

```bash
# 1. Initialize the connection
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-11-25",
      "capabilities": {},
      "clientInfo": {"name": "curl-test", "version": "1.0"}
    }
  }'

# 2. Send the initialized notification
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "notifications/initialized"
  }'

# 3. List available tools
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 2, "method": "tools/list"}'

# 4. Call the bible_lookup tool
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "bible_lookup",
      "arguments": {"reference": "John 3:16", "version": "KJV"}
    }
  }'
```

### MCP Controller (app/controllers/mcp_controller.rb)

```ruby
class McpController < ApplicationController
  include ActiveIntelligence::MCP::RailsController

  # Register tools to expose via MCP
  mcp_tools BibleReferenceTool

  # Server identification
  mcp_server_name 'Bible Study MCP Server'
  mcp_server_version '1.0.0'

  protected

  # Optional: Add authentication
  # def authenticate_mcp_request
  #   api_key = request.headers['X-API-Key']
  #   api_key == Rails.application.credentials.mcp_api_key
  # end

  # Optional: Logging
  def before_tool_call(tool_name, params)
    Rails.logger.info "[MCP] Calling tool: #{tool_name}"
  end
end
```

### Using with Claude Desktop

To use this MCP server with Claude Desktop, you would need to set up an HTTP transport. Claude Desktop currently supports stdio-based MCP servers. For HTTP servers like this one, you can:

1. Use a tool like [mcp-proxy](https://github.com/anthropics/mcp-proxy) to bridge HTTP to stdio
2. Wait for direct HTTP support in Claude Desktop
3. Use another MCP client that supports HTTP transport

### Available MCP Methods

| Method | Description |
|--------|-------------|
| `initialize` | Establish connection and negotiate capabilities |
| `notifications/initialized` | Signal that client is ready |
| `ping` | Health check |
| `tools/list` | List available tools and their schemas |
| `tools/call` | Execute a tool with arguments |

## Customization Ideas

### Add More Tools

```ruby
# app/tools/bible_search_tool.rb
class BibleSearchTool < ActiveIntelligence::Tool
  name "bible_search"
  description "Search the Bible for keywords or phrases"

  param :query, type: String, required: true

  def execute(params)
    # Implement search logic
  end
end

# Register in agent
class BibleStudyAgent < ActiveIntelligence::Agent
  # ...
  tool BibleReferenceTool
  tool BibleSearchTool  # Add new tool
end
```

### Add User Authentication

```ruby
# Add user_id to conversations migration
add_column :active_intelligence_conversations, :user_id, :integer
add_foreign_key :active_intelligence_conversations, :users

# In controller
def create
  @conversation = current_user.conversations.create!(
    agent_class: 'BibleStudyAgent'
  )
end
```

### Add Different Bible Versions

The BibleReferenceTool already supports KJV, ASV, and WEB. You can add more:

```ruby
param :version,
      type: String,
      required: false,
      default: "KJV",
      enum: ["KJV", "ASV", "WEB", "NIV", "ESV"],
      description: "Bible translation"
```

### Add Commentary Tool

```ruby
class BibleCommentaryTool < ActiveIntelligence::Tool
  name "get_commentary"
  description "Get scholarly commentary on a Bible passage"

  param :reference, type: String, required: true

  def execute(params)
    # Fetch from commentary API
  end
end
```

## Troubleshooting

### "ANTHROPIC_API_KEY not configured"

Make sure you've set the environment variable:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

### Database errors

Reset the database:

```bash
bundle exec rails db:drop db:create db:migrate
```

### Streaming not working

1. Make sure you're using Puma (not WEBrick)
2. Check that ActionController::Live is included
3. Check browser console for errors

### Tool not being called

1. Check that the tool is registered: `tool BibleReferenceTool`
2. Check the tool's description - make sure it's clear when to use it
3. Look at the database to see what messages were saved

## Learning Points

This example demonstrates:

1. **Memory Strategy** - Using `:active_record` instead of `:in_memory`
2. **Tool Creation** - Building tools that interact with external APIs
3. **Agent Identity** - Crafting effective system prompts
4. **Streaming** - Implementing real-time response streaming
5. **Persistence** - How conversations are stored and retrieved
6. **Rails Integration** - Clean patterns for Rails applications

## Next Steps

- Add user authentication and multi-tenancy
- Implement conversation search and filtering
- Add more specialized Bible tools
- Build a mobile-responsive design
- Add background job processing for long conversations
- Implement conversation export (PDF, markdown)

## Resources

- [ActiveIntelligence Gem](../../README.md)
- [Rails Integration Guide](../../RAILS_INTEGRATION.md)
- [Bible API](https://bible-api.com)
- [Anthropic Claude Docs](https://docs.anthropic.com)

## License

MIT (same as ActiveIntelligence gem)
