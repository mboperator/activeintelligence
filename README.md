# ActiveIntelligence

A Ruby gem for building AI agents powered by Claude (Anthropic's LLM). Create conversational agents with tool-calling capabilities, memory management, and streaming support using a clean, intuitive DSL.

> **For AI Coding Agents**: See [CLAUDE.md](CLAUDE.md) for a comprehensive cheat sheet and development guide.

## Features

- **Clean DSL**: Define agents and tools with an intuitive, declarative syntax
- **Advanced Tool Calling**: Multiple tools per turn with automatic loop-until-completion
- **Streaming Support**: Real-time streaming responses with Server-Sent Events
- **Memory Management**: Built-in conversation history tracking
- **Error Handling**: Comprehensive error handling with proper API error formatting
- **Type Safety**: Automatic parameter validation and JSON schema generation
- **Claude Integration**: First-class support for Anthropic's Claude models
- **Prompt Caching**: Built-in support for 80-90% cost reduction via prompt caching
- **Extended Thinking**: Captures Claude's reasoning process for complex tasks
- **Production-Ready**: Optimized for Claude Code-level performance
- **Observability**: Comprehensive metrics, logging, callbacks, and ActiveSupport::Notifications

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'activeintelligence.rb'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install activeintelligence.rb
```

**Environment Setup**:
```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```

## Quick Start

### CLI/Standalone Usage

```ruby
require 'activeintelligence'
require_relative 'your_custom_tool'

# 1. Configure the gem
ActiveIntelligence.configure do |config|
  config.settings[:claude][:model] = "claude-3-sonnet-20240229"
  config.settings[:logger] = Logger.new(STDOUT, level: Logger::INFO)
end

# 2. Define your agent
class AssistantAgent < ActiveIntelligence::Agent
  model    :claude
  memory   :in_memory
  identity "You are a helpful assistant."

  # Register tools (optional)
  tool YourCustomTool
end

# 3. Create and use your agent
agent = AssistantAgent.new(objective: "Help the user with their tasks")
response = agent.send_message("What can you help me with today?")
puts response

# 4. Streaming responses
agent.send_message("Tell me a story", stream: true) do |chunk|
  print chunk
  $stdout.flush
end
```

### Rails Integration

ActiveIntelligence seamlessly integrates with Rails applications for persistent, multi-user conversations.

```bash
# Add to Gemfile
gem 'activeintelligence.rb'

# Install and run generator
bundle install
rails generate active_intelligence:install
rails db:migrate
```

**Create an agent:**
```ruby
# app/agents/customer_support_agent.rb
class CustomerSupportAgent < ActiveIntelligence::Agent
  model :claude
  memory :active_record  # Database-backed persistence!
  identity "You are a helpful customer support agent"

  tool OrderLookupTool
end
```

**Use in controllers:**
```ruby
# app/controllers/conversations_controller.rb
class ConversationsController < ApplicationController
  include ActiveIntelligence::ConversationManageable

  def create
    @conversation = current_user.active_intelligence_conversations.create!(
      agent_class: 'CustomerSupportAgent'
    )
    render json: { id: @conversation.id }
  end

  def send_message
    @conversation = current_user.active_intelligence_conversations.find(params[:id])
    response = send_agent_message(params[:message], conversation: @conversation)
    render json: { response: response }
  end
end
```

**Key Features for Rails:**
- ✅ Database-backed conversation persistence
- ✅ Multi-user support with user scoping
- ✅ Streaming via ActionController::Live
- ✅ Background job support for long-running agents
- ✅ ActiveRecord models for conversations and messages

📖 **See [RAILS_INTEGRATION.md](RAILS_INTEGRATION.md) for complete Rails documentation.**

## Core Concepts

### Agents

Agents are the central components that interact with the LLM and manage conversations.

```ruby
class ResearchAgent < ActiveIntelligence::Agent
  model    :claude         # Currently supported: :claude
  memory   :in_memory      # Memory strategy: :in_memory or :active_record
  identity "You are an expert researcher who finds accurate information."

  # Register tools
  tool WebSearchTool
  tool WikipediaTool
end

# Initialize with more options
agent = ResearchAgent.new(
  objective: "Research scientific topics and provide accurate information",
  options: {
    model: "claude-3-opus-20240229",  # Override class settings
    max_tokens: 4000,
    api_key: ENV['ANTHROPIC_API_KEY']
  }
)

# For Rails with database persistence:
class RailsAgent < ActiveIntelligence::Agent
  model    :claude
  memory   :active_record  # Persists to database
  identity "You are a helpful assistant"
end

# Initialize with a conversation record
conversation = ActiveIntelligence::Conversation.find(123)
agent = RailsAgent.new(conversation: conversation)
```

### Tools

Tools allow your agent to perform actions and access external data. Tools inherit from `ActiveIntelligence::Tool` and use a DSL to define their interface.

#### Creating a Tool

```ruby
class WeatherTool < ActiveIntelligence::Tool
  name "get_weather"  # Custom name (defaults to underscored class name)
  description "Get current weather for a location"

  # Define parameters with type validation
  param :location, type: String, required: true,
        description: "City name or coordinates"
  param :unit, type: String, required: false, default: "celsius",
        enum: ["celsius", "fahrenheit"],
        description: "Temperature unit"

  def execute(params)
    # Implement your tool logic here
    # Access validated params via hash: params[:location], params[:unit]
    temp = call_weather_api(params[:location], params[:unit])

    # Return formatted success response
    success_response({
      location: params[:location],
      temperature: temp,
      unit: params[:unit]
    })
  end

  # Optional: Handle specific errors
  rescue_from WeatherApiError do |e, params|
    error_response("Weather data not available: #{e.message}")
  end

  private

  def call_weather_api(location, unit)
    # Your API logic here
  end
end
```

#### Tool Response Format

Tools must return structured responses:

```ruby
# Success response
success_response({ key: "value", data: {...} })
# Returns: { success: true, data: { key: "value", data: {...} } }

# Error response
error_response("Something went wrong", details: { code: 500 })
# Returns: { error: true, message: "Something went wrong", details: { code: 500 } }
```

### Advanced Usage

#### Streaming Responses

```ruby
# Streaming responses with real-time output
agent.send_message("Tell me a story about robots", stream: true) do |chunk|
  print chunk
  $stdout.flush
end

# Note: Tool calls are handled automatically in streaming mode
# The agent will detect tool use, execute the tool, and continue streaming
```

#### Error Handling

```ruby
class DataTool < ActiveIntelligence::Tool
  # ...
  
  # Define custom error handling
  on_error :not_found do |params|
    { error: true, message: "Data not found for #{params[:id]}" }
  end
  
  rescue_from API::ConnectionError, with: :handle_connection_error
  
  def execute(params)
    # ... implementation
    raise ToolError.new("Custom error message", status: :validation_failed)
  end
  
  private
  
  def handle_connection_error(error, params)
    error_response("Connection failed: #{error.message}", 
                  details: { retry_after: 30 })
  end
end
```

## Observability & Monitoring

ActiveIntelligence includes comprehensive observability features for production use. Track metrics, monitor performance, and integrate with your monitoring tools.

### Metrics

Every agent tracks detailed metrics including tokens, costs, latency, and success rates:

```ruby
agent = MyAgent.new
agent.send_message("Hello")
agent.send_message("Tell me a joke")

# Access detailed metrics
puts agent.metrics.to_h
# => {
#      messages: { total: 4, user: 2, agent: 2 },
#      tokens: { total: 523, input: 123, output: 400, cached: 100, cache_hit_rate_percent: 81.3 },
#      api_calls: { total: 2, average_latency_ms: 1234.56, p95_latency_ms: 1500.0 },
#      tool_calls: { total: 3, average_latency_ms: 45.23, by_tool: { "DadJokeTool" => 3 } },
#      estimated_cost_usd: 0.0234
#    }

# Pretty print for humans
puts agent.metrics.to_s
```

### Lifecycle Callbacks

Hook into the agent execution lifecycle:

```ruby
class MyAgent < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity "You are a helpful assistant"

  # Track all messages
  before_message do |data|
    puts "Sending: #{data[:content]}"
  end

  after_message do |data|
    puts "Response received in #{data[:metrics][:api_calls][:average_latency_ms]}ms"
    puts "Total cost so far: $#{data[:metrics][:estimated_cost_usd]}"

    # Send to monitoring
    StatsD.gauge('ai.conversation_length', data[:message_count])
  end

  # Monitor tool performance
  after_tool_call do |data|
    puts "Tool #{data[:tool_name]} took #{data[:duration_ms]}ms"

    # Track in APM
    NewRelic::Agent.record_metric("AI/Tool/#{data[:tool_name]}", data[:duration_ms])
  end

  # Error tracking
  on_error do |data|
    Sentry.capture_exception(data[:error], extra: data[:context])
  end
end
```

### ActiveSupport::Notifications

Integrate with Rails monitoring tools:

```ruby
# Subscribe to all AI events
ActiveSupport::Notifications.subscribe(/\.activeintelligence$/) do |name, start, finish, id, payload|
  duration = (finish - start) * 1000
  Rails.logger.info("AI Event: #{name}, Duration: #{duration}ms")

  # Automatically integrates with Scout, New Relic, Datadog, etc.
end

# Subscribe to specific events
ActiveSupport::Notifications.subscribe('api_call.activeintelligence') do |name, start, finish, id, payload|
  StatsD.histogram('ai.api_call.duration', (finish - start) * 1000)
  StatsD.gauge('ai.tokens_used', payload[:usage][:total_tokens])
end
```

### Structured Logging

Configure detailed logging for debugging and monitoring:

```ruby
ActiveIntelligence.configure do |config|
  config.settings[:log_level] = :info              # :debug, :info, :warn, :error
  config.settings[:log_api_requests] = false       # Log full API requests
  config.settings[:log_tool_executions] = true     # Log tool executions
  config.settings[:log_token_usage] = true         # Log token consumption
  config.settings[:structured_logging] = true      # JSON-formatted logs
end

# Logs are emitted as structured JSON:
# {"timestamp":"2024-11-15T10:30:45Z","event":"api_response","provider":"claude",
#  "duration_ms":1234.56,"usage":{"total_tokens":523},"stop_reason":"end_turn"}
```

**For complete documentation**, see [OBSERVABILITY.md](OBSERVABILITY.md).

## API Reference

### Agent DSL

- `model` - Set the underlying LLM model
- `memory` - Configure message history strategy
- `identity` - Set the system prompt/identity
- `tool` - Register tools

### Tool DSL

- `name` - Set the tool name for LLM APIs
- `description` - Describe the tool's purpose
- `param` - Define a parameter with validation
- `on_error` - Add error handlers
- `rescue_from` - Handle exceptions

### Parameter Types

- `type`: Ruby classes (String, Integer, Float, Array, Hash, etc.)
- `required`: true/false
- `description`: Parameter description for the LLM
- `default`: Default value
- `enum`: Array of allowed values

## Configuration

```ruby
ActiveIntelligence.configure do |config|
  # Claude settings
  config.settings[:claude][:model] = "claude-3-opus-20240229"
  config.settings[:claude][:api_version] = "2023-06-01"
  config.settings[:claude][:max_tokens] = 4096  # Default: 4096 (increased for complex tasks)
  config.settings[:claude][:enable_prompt_caching] = true  # Default: true (80-90% cost savings)

  # Logging (set to DEBUG to see Claude's thinking process)
  config.settings[:logger] = defined?(Rails) ?
    Rails.logger : Logger.new(STDOUT, level: Logger::INFO)

  # Observability settings
  config.settings[:log_level] = :info              # :debug, :info, :warn, :error
  config.settings[:log_api_requests] = false       # Log full API request/response
  config.settings[:log_tool_executions] = true     # Log tool call executions
  config.settings[:log_token_usage] = true         # Log token consumption and costs
  config.settings[:structured_logging] = true      # Use JSON structured logging
  config.settings[:enable_notifications] = true    # Enable ActiveSupport::Notifications
end
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `model` | `claude-3-opus-20240229` | Claude model to use |
| `api_version` | `2023-06-01` | Anthropic API version |
| `max_tokens` | `4096` | Maximum tokens per response |
| `enable_prompt_caching` | `true` | Enable prompt caching for cost savings |
| `logger` | `Logger.new(STDOUT)` | Logger instance for debugging |
| `log_level` | `:info` | Logging verbosity level |
| `log_api_requests` | `false` | Log full API requests/responses (debug mode) |
| `log_tool_executions` | `true` | Log tool execution events |
| `log_token_usage` | `true` | Log token consumption and costs |
| `structured_logging` | `true` | Use JSON-formatted structured logs |
| `enable_notifications` | `true` | Enable ActiveSupport::Notifications instrumentation |

## Supported Models

ActiveIntelligence works with Anthropic's Claude models:

- `claude-3-opus-20240229` - Most capable model
- `claude-3-sonnet-20240229` - Balanced performance
- `claude-3-5-sonnet-latest` - Latest Sonnet version
- `claude-3-5-haiku-latest` - Fastest, most cost-effective

## Environment Variables

- `ANTHROPIC_API_KEY`: Your Anthropic API key (required)

## Examples

See the `bin/` directory for working examples:

- **Dad Joke Agent** (`bin/dad_joke_agent.rb`) - Simple agent with custom tool
- **Dad Joke Agent (Streaming)** (`bin/dad_joke_agent_streaming.rb`) - Streaming version
- **Concordance Agent** (`bin/concordance_agent.rb`) - Seminary professor assistant
- **Concordance Agent (Streaming)** (`bin/concordance_agent_streaming.rb`) - Streaming version

Run an example:
```bash
export ANTHROPIC_API_KEY="your-key-here"
ruby bin/dad_joke_agent.rb
```

## Development

### Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/activeintelligence.git
cd activeintelligence

# Install dependencies
bundle install
```

### Running Tests

```bash
# Run all tests
rake spec

# Run linter
rake rubocop

# Run both tests and linter
rake
```

### Building the Gem

```bash
# Build
rake build

# Install locally
rake install

# The gem will be in pkg/activeintelligence.rb-0.0.1.gem
```

## Architecture

```
┌─────────────────────┐
│   Your Agent Class  │  (inherits from ActiveIntelligence::Agent)
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Agent (agent.rb)   │  Manages conversation, tool execution
└──────────┬──────────┘
           │
           ├──────────────────────┬─────────────────────┐
           ▼                      ▼                     ▼
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│  ClaudeClient    │   │  Your Tools      │   │  Messages        │
│  (API Client)    │   │  (Custom Logic)  │   │  (History)       │
└──────────────────┘   └──────────────────┘   └──────────────────┘
           │
           ▼
┌──────────────────────┐
│  Anthropic Claude    │
│  Messages API        │
└──────────────────────┘
```

## Project Structure

```
activeintelligence/
├── lib/
│   ├── activeintelligence/
│   │   ├── agent.rb              # Core agent class with DSL
│   │   ├── tool.rb               # Base tool class with validation
│   │   ├── api_clients/
│   │   │   ├── base_client.rb    # Abstract API client
│   │   │   └── claude_client.rb  # Claude API implementation
│   │   ├── messages.rb           # Message type system
│   │   ├── config.rb             # Configuration management
│   │   └── errors.rb             # Error classes
│   └── activeintelligence.rb     # Main entry point
├── bin/                          # Example agents
├── spec/                         # Test files
├── CLAUDE.md                     # AI agent development guide
└── README.md                     # This file
```

## Performance & Optimizations

ActiveIntelligence is optimized for production use with Claude Code-level performance:

### Intelligent Tool Calling
- **Multiple tools per turn**: Execute all tool calls from a single response in parallel
- **Loop until completion**: Automatically continues tool execution until task is complete
- **Proper error handling**: Tool errors are formatted correctly with `is_error` flag
- **Smart message formatting**: Combines consecutive tool results to maintain API compliance

### Cost Optimization
- **Prompt caching enabled by default**: 80-90% cost reduction on repeated content
- **Automatic cache points**: System prompts and tool schemas are cached intelligently
- **Configurable**: Disable with `enable_prompt_caching: false` if needed

```ruby
# Caching is automatic, but can be controlled
agent = MyAgent.new(
  options: { enable_prompt_caching: true }  # Default
)
```

### Performance Metrics
- **3-10x fewer API calls** for multi-tool workflows
- **2-5x faster** tool execution through parallel processing
- **80%+ cost savings** on multi-turn conversations
- **4096 max_tokens** default (up from 1024) for complex responses

### Additional Features
- **Extended thinking support**: Captures Claude's reasoning (logged at debug level)
- **Stop reason validation**: Detects truncated responses and logs warnings
- **Loop protection**: Maximum 25 iterations prevents infinite loops
- **Message alternation**: Automatic handling of user/assistant role requirements

## How It Works

1. **Agent receives message** → Added to conversation history
2. **Agent formats messages** → Converts to structured Claude API format with caching
3. **API client calls Claude** → Sends messages + cached tool schemas
4. **Claude responds** → Either text, tool_use block(s), or both
5. **If tool_use** (automatic loop):
   - Agent executes **all** tools with validated params (in parallel-ready format)
   - All tool results added to history as single message
   - Agent calls Claude again with results
   - **Repeats** until Claude responds with text only (max 25 iterations)
6. **Final response** → Returned to user

### Example: Multi-Tool Workflow

```ruby
# User: "Read files A, B, and C, then summarize them"
#
# Turn 1: Claude requests [read(A), read(B), read(C)]
# → All 3 tools execute
# → Results sent back in one API call
#
# Turn 2: Claude requests [summarize(A+B+C)]
# → Summarize tool executes
# → Result sent back
#
# Turn 3: Claude responds with summary text
# → Complete! (3 API calls instead of 7+)
```

## Contributing

Contributions are welcome! Here's how to get started:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes and add tests
4. Run the test suite (`rake spec`)
5. Run the linter (`rake rubocop`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### For AI Coding Agents

If you're an AI agent working on this codebase, please read [CLAUDE.md](CLAUDE.md) first for a comprehensive development guide.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Author

Marcus Bernales

## Version

0.0.1
