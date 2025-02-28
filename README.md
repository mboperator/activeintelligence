# ActiveIntelligence

A gem for building AI agents.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'activeintelligence'
```

And then execute:

```
$ bundle install
```

Or install it yourself as:

```
$ gem install activeintelligence
```

## Quick Start

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

## Core Concepts

### Agents

Agents are the central components that interact with the LLM and manage conversations.

```ruby
class ResearchAgent < ActiveIntelligence::Agent
  model    :claude      # Currently supported: :claude
  memory   :in_memory   # Memory strategy
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
```

### Tools

Tools allow your agent to perform actions and access external data.

#### Creating Query Tools (read-only)

```ruby
class WeatherTool < ActiveIntelligence::QueryTool
  name "get_weather"  # Custom name (defaults to underscored class name)
  description "Get current weather for a location"
  
  # Define parameters
  param :location, type: String, required: true, 
        description: "City name or coordinates"
  param :unit, type: String, required: false, default: "celsius",
        enum: ["celsius", "fahrenheit"],
        description: "Temperature unit"
        
  def execute(params)
    # Implement API call or data lookup
    temp = call_weather_api(params[:location], params[:unit])
    
    # Return formatted success response
    success_response({
      location: params[:location],
      temperature: temp,
      unit: params[:unit]
    })
  end
  
  # Handle specific errors (optional)
  rescue_from WeatherApiError do |e, params|
    error_response("Weather data not available: #{e.message}")
  end
end
```

#### Creating Command Tools (with side effects)

```ruby
class SaveNoteTool < ActiveIntelligence::CommandTool
  name "save_note"
  description "Save a note to the database"
  
  param :title, type: String, required: true
  param :content, type: String, required: true
  param :tags, type: Array, required: false
  
  def execute(params)
    # Create a record in the database
    note = Note.create!(
      title: params[:title],
      content: params[:content],
      tags: params[:tags]
    )
    
    success_response({
      id: note.id,
      title: note.title,
      status: "saved"
    })
  end
end
```

### Advanced Usage

#### Streaming with Tool Calls

```ruby
# Handle streaming with tool calls
agent.send_message("What's the weather in London?", stream: true) do |chunk|
  # Tool calls are sent as specially formatted chunks
  if chunk.start_with?("[") && chunk.end_with?("]")
    puts "\nExecuting tool: #{chunk}"
  else
    print chunk
    $stdout.flush
  end
end
```

#### Error Handling

```ruby
class DataTool < ActiveIntelligence::QueryTool
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
  config.settings[:claude][:max_tokens] = 4000
  
  # Logging
  config.settings[:logger] = defined?(Rails) ? 
    Rails.logger : Logger.new(STDOUT, level: Logger::INFO)
end
```

## Environment Variables

- `ANTHROPIC_API_KEY`: Your Anthropic API key for Claude models

## Examples

See examples directory for complete implementations:
- Weather assistant
- Customer support agent
- Research assistant
- Task management agent

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create new Pull Request
