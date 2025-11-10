# Rails Integration Guide

This guide shows you how to integrate ActiveIntelligence into your Rails application for persistent, multi-user AI agent conversations.

## Table of Contents

- [Installation](#installation)
- [Setup](#setup)
- [Database Models](#database-models)
- [Creating Agents](#creating-agents)
- [Controller Integration](#controller-integration)
- [Streaming Support](#streaming-support)
- [User Scoping](#user-scoping)
- [Example Application](#example-application)
- [Advanced Usage](#advanced-usage)

## Installation

Add ActiveIntelligence to your Gemfile:

```ruby
gem 'activeintelligence.rb'
```

Then run:

```bash
bundle install
rails generate active_intelligence:install
rails db:migrate
```

This will create:
- Database migrations for conversations and messages
- ActiveRecord models
- Controller concern for easy integration
- Initializer for configuration

## Setup

### 1. Configure API Key

Set your Anthropic API key in one of these ways:

**Option A: Environment Variable (Recommended)**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

**Option B: Rails Credentials**
```bash
rails credentials:edit
```

Add:
```yaml
anthropic:
  api_key: sk-ant-...
```

**Option C: Initializer**

Edit `config/initializers/active_intelligence.rb`:

```ruby
ActiveIntelligence.configure do |config|
  config.anthropic_api_key = "sk-ant-..."
end
```

### 2. Verify Installation

Check that the models were created:

```bash
rails runner "puts ActiveIntelligence::Conversation.count"
```

## Database Models

### Conversation Model

The `ActiveIntelligence::Conversation` model stores conversation metadata:

```ruby
# Schema
create_table :active_intelligence_conversations do |t|
  t.references :user                    # Optional: link to your User model
  t.string :agent_class, null: false   # Which agent class to use
  t.string :status, default: 'active'   # active, archived
  t.text :objective                     # Agent objective/goal
  t.json :metadata, default: {}         # Custom metadata
  t.timestamps
end
```

**Key Methods:**
- `conversation.agent(options: {}, tools: nil)` - Initialize agent instance
- `conversation.archive!` - Archive the conversation
- `conversation.last_message` - Get most recent message
- `conversation.message_count` - Count messages

### Message Model

The `ActiveIntelligence::Message` model stores individual messages:

```ruby
# Schema
create_table :active_intelligence_messages do |t|
  t.references :conversation, null: false
  t.string :role, null: false           # user, assistant, tool
  t.text :content                       # Message content
  t.json :tool_calls, default: []       # Tool calls from assistant
  t.string :tool_name                   # Tool name for tool messages
  t.json :metadata, default: {}         # Custom metadata
  t.timestamps
end
```

**Scopes:**
- `Message.user_messages` - Only user messages
- `Message.assistant_messages` - Only assistant messages
- `Message.tool_messages` - Only tool responses

## Creating Agents

### Define Your Agent Class

Create your agent in `app/agents/` (you may need to create this directory):

```ruby
# app/agents/customer_support_agent.rb
class CustomerSupportAgent < ActiveIntelligence::Agent
  model :claude
  memory :active_record  # Use database-backed memory
  identity "You are a helpful customer support agent. Be friendly and professional."

  # Register tools
  tool OrderLookupTool
  tool RefundProcessorTool
end
```

**Important:** Set `memory :active_record` to enable database persistence.

### Create Tools for Your Agent

```ruby
# app/tools/order_lookup_tool.rb
class OrderLookupTool < ActiveIntelligence::Tool
  name "order_lookup"
  description "Look up order details by order number"

  param :order_number, type: String, required: true, description: "The order number"

  def execute(params)
    order = Order.find_by(number: params[:order_number])

    if order
      success_response({
        order_number: order.number,
        status: order.status,
        total: order.total,
        items: order.items.count
      })
    else
      error_response("Order not found", details: { order_number: params[:order_number] })
    end
  rescue => e
    error_response("Failed to lookup order", details: e.message)
  end
end
```

## Controller Integration

### Basic Controller Setup

```ruby
# app/controllers/conversations_controller.rb
class ConversationsController < ApplicationController
  include ActiveIntelligence::ConversationManageable

  before_action :authenticate_user!  # Your authentication

  # Create a new conversation
  def create
    @conversation = current_user.active_intelligence_conversations.create!(
      agent_class: 'CustomerSupportAgent',
      objective: params[:objective]
    )

    render json: {
      id: @conversation.id,
      agent_class: @conversation.agent_class,
      created_at: @conversation.created_at
    }
  end

  # List conversations
  def index
    @conversations = current_user.active_intelligence_conversations
                                 .active
                                 .order(updated_at: :desc)

    render json: @conversations
  end

  # Get conversation details
  def show
    @conversation = current_user.active_intelligence_conversations.find(params[:id])

    render json: {
      conversation: @conversation,
      messages: @conversation.messages.order(:created_at)
    }
  end

  # Send a message (non-streaming)
  def send_message
    @conversation = current_user.active_intelligence_conversations.find(params[:id])

    response = send_agent_message(
      params[:message],
      conversation: @conversation
    )

    render json: {
      response: response,
      message_count: @conversation.message_count
    }
  end

  # Archive conversation
  def archive
    @conversation = current_user.active_intelligence_conversations.find(params[:id])
    @conversation.archive!

    head :no_content
  end

  private

  # Override to scope to current user
  def conversation_scope
    current_user.active_intelligence_conversations
  end
end
```

### Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  resources :conversations, only: [:index, :show, :create] do
    member do
      post :send_message
      post :send_message_streaming
      put :archive
    end
  end
end
```

## Streaming Support

For real-time streaming responses, use ActionController::Live:

```ruby
class ConversationsController < ApplicationController
  include ActionController::Live
  include ActiveIntelligence::ConversationManageable

  def send_message_streaming
    @conversation = current_user.active_intelligence_conversations.find(params[:id])

    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['X-Accel-Buffering'] = 'no'  # Disable nginx buffering
    response.headers['Cache-Control'] = 'no-cache'

    begin
      agent = @conversation.agent

      agent.send_message(params[:message], stream: true) do |chunk|
        response.stream.write "data: #{chunk}\n\n"
      end

      response.stream.write "data: [DONE]\n\n"
    rescue IOError
      # Client disconnected
      logger.info "Client disconnected from stream"
    ensure
      response.stream.close
    end
  end
end
```

### Client-Side JavaScript (SSE)

```javascript
// Using EventSource API
function sendStreamingMessage(conversationId, message) {
  const eventSource = new EventSource(
    `/conversations/${conversationId}/send_message_streaming?message=${encodeURIComponent(message)}`
  );

  eventSource.onmessage = (event) => {
    if (event.data === '[DONE]') {
      eventSource.close();
      return;
    }

    // Append chunk to UI
    appendToChat(event.data);
  };

  eventSource.onerror = (error) => {
    console.error('Stream error:', error);
    eventSource.close();
  };
}

// Using fetch with ReadableStream (more control)
async function sendStreamingMessageFetch(conversationId, message) {
  const response = await fetch(`/conversations/${conversationId}/send_message_streaming`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream'
    },
    body: JSON.stringify({ message })
  });

  const reader = response.body.getReader();
  const decoder = new TextDecoder();

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    const chunk = decoder.decode(value);
    const lines = chunk.split('\n\n');

    lines.forEach(line => {
      if (line.startsWith('data: ')) {
        const data = line.substring(6);
        if (data !== '[DONE]') {
          appendToChat(data);
        }
      }
    });
  }
}
```

## User Scoping

### Add Association to User Model

```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_many :active_intelligence_conversations,
           class_name: 'ActiveIntelligence::Conversation',
           dependent: :destroy

  # Helper to create a new conversation
  def start_conversation(agent_class, objective: nil, **options)
    active_intelligence_conversations.create!(
      agent_class: agent_class,
      objective: objective,
      **options
    )
  end
end
```

### Update Migration (if not already done)

The generated migration includes an optional `user_id` foreign key. If you need to make it required:

```ruby
# In migration
t.references :user, foreign_key: true, null: false  # Make required
```

## Example Application Flow

### 1. User starts a conversation

```ruby
POST /conversations
{
  "agent_class": "CustomerSupportAgent",
  "objective": "Help with order issues"
}

Response:
{
  "id": 123,
  "agent_class": "CustomerSupportAgent",
  "created_at": "2024-01-01T12:00:00Z"
}
```

### 2. User sends first message

```ruby
POST /conversations/123/send_message
{
  "message": "I need help with order #12345"
}

Response:
{
  "response": "I'd be happy to help you with order #12345. Let me look that up for you...",
  "message_count": 2
}
```

### 3. Agent uses tools automatically

The agent will:
1. Recognize it needs to look up the order
2. Call `OrderLookupTool` with order number
3. Get the results
4. Respond to the user with order details

All of this happens automatically and is persisted to the database.

### 4. Conversation continues

```ruby
POST /conversations/123/send_message
{
  "message": "Can I get a refund?"
}

Response:
{
  "response": "Let me process that refund for you...",
  "message_count": 4
}
```

### 5. Later: User returns to same conversation

```ruby
GET /conversations/123

Response:
{
  "conversation": { "id": 123, ... },
  "messages": [
    { "role": "user", "content": "I need help with order #12345" },
    { "role": "assistant", "content": "I'd be happy to help..." },
    { "role": "user", "content": "Can I get a refund?" },
    { "role": "assistant", "content": "Let me process that..." }
  ]
}
```

The conversation history is automatically loaded when you send a new message.

## Advanced Usage

### Custom Conversation Attributes

Add custom attributes to conversations:

```ruby
# Migration
add_column :active_intelligence_conversations, :department, :string
add_column :active_intelligence_conversations, :priority, :integer

# Usage
conversation = current_user.start_conversation(
  'CustomerSupportAgent',
  department: 'billing',
  priority: 1
)
```

### Different Agents Per Conversation

```ruby
# Create specialized agents
class BillingAgent < ActiveIntelligence::Agent
  model :claude
  memory :active_record
  identity "You are a billing specialist"
  tool BillingTool
end

class TechnicalSupportAgent < ActiveIntelligence::Agent
  model :claude
  memory :active_record
  identity "You are a technical support specialist"
  tool TroubleshootingTool
end

# In controller
def create
  agent_class = params[:department] == 'billing' ? 'BillingAgent' : 'TechnicalSupportAgent'

  @conversation = current_user.start_conversation(agent_class)
  render json: @conversation
end
```

### Background Jobs for Long Responses

For very long-running agent operations, use background jobs:

```ruby
# app/jobs/agent_message_job.rb
class AgentMessageJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, message, user_id)
    conversation = ActiveIntelligence::Conversation.find(conversation_id)
    agent = conversation.agent

    response = agent.send_message(message)

    # Broadcast via ActionCable
    ConversationChannel.broadcast_to(
      conversation,
      { type: 'message', content: response }
    )
  end
end

# In controller
def send_message_async
  @conversation = current_user.active_intelligence_conversations.find(params[:id])

  AgentMessageJob.perform_later(
    @conversation.id,
    params[:message],
    current_user.id
  )

  render json: { status: 'processing' }
end
```

### Context and Metadata

Store custom context in message metadata:

```ruby
# When creating a message, add metadata
conversation.messages.create!(
  role: 'user',
  content: 'Hello',
  metadata: {
    ip_address: request.remote_ip,
    user_agent: request.user_agent,
    session_id: session.id
  }
)

# Query messages by metadata (PostgreSQL JSONB)
conversation.messages.where("metadata->>'session_id' = ?", session.id)
```

### Conversation Analytics

```ruby
# app/models/active_intelligence/conversation.rb
class ActiveIntelligence::Conversation
  # Custom scopes
  scope :by_agent, ->(agent_class) { where(agent_class: agent_class) }
  scope :recent, -> { where('created_at > ?', 1.week.ago) }

  # Analytics methods
  def average_response_time
    assistant_messages = messages.assistant_messages.order(:created_at)
    user_messages = messages.user_messages.order(:created_at)

    times = user_messages.zip(assistant_messages).map do |user_msg, assistant_msg|
      next unless assistant_msg
      (assistant_msg.created_at - user_msg.created_at).to_f
    end.compact

    times.sum / times.size if times.any?
  end

  def tool_usage_stats
    messages.assistant_messages.where.not(tool_calls: []).group_by do |msg|
      msg.parsed_tool_calls.first&.dig('name')
    end.transform_values(&:count)
  end
end
```

## Performance Considerations

### Database Indexing

The generator creates indexes on:
- `conversation_id` for messages
- `role` for messages
- `status` for conversations
- `agent_class` for conversations

For high-traffic apps, consider adding:

```ruby
add_index :active_intelligence_messages, [:conversation_id, :role]
add_index :active_intelligence_conversations, [:user_id, :status]
```

### Message Cleanup

Implement a job to archive old messages:

```ruby
# app/jobs/cleanup_old_messages_job.rb
class CleanupOldMessagesJob < ApplicationJob
  def perform
    # Archive conversations older than 90 days
    ActiveIntelligence::Conversation
      .where('created_at < ?', 90.days.ago)
      .where(status: 'active')
      .find_each(&:archive!)
  end
end
```

### Pagination

Paginate message history for large conversations:

```ruby
def show
  @conversation = current_user.active_intelligence_conversations.find(params[:id])
  @messages = @conversation.messages
                           .order(created_at: :desc)
                           .page(params[:page])
                           .per(50)

  render json: {
    conversation: @conversation,
    messages: @messages,
    pagination: {
      current_page: @messages.current_page,
      total_pages: @messages.total_pages
    }
  }
end
```

## Troubleshooting

### "Conversation required for :active_record memory"

Make sure you're passing a conversation object when initializing the agent:

```ruby
# Wrong
agent = MyAgent.new

# Right
agent = conversation.agent
# or
agent = MyAgent.new(conversation: conversation)
```

### "Failed to load messages from database"

Check that your conversation has the `messages` association:

```ruby
ActiveIntelligence::Conversation.reflect_on_association(:messages)
```

### Streaming not working

1. Check that `ActionController::Live` is included
2. Check server configuration (Puma, not WEBrick)
3. Check that nginx buffering is disabled
4. Check browser console for CORS issues

### Messages not persisting

1. Verify `memory :active_record` is set on your agent
2. Check database permissions
3. Check Rails logs for ActiveRecord errors

## Next Steps

- Read the [main README](README.md) for more on tool creation
- Check out the [CLAUDE.md](CLAUDE.md) for architecture details
- Build your first agent following these examples

For questions or issues, please open an issue on GitHub.
