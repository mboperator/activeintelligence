# ActiveIntelligence Observability Guide

This guide covers all observability features in ActiveIntelligence, including metrics, logging, instrumentation, and callbacks.

## Table of Contents

1. [Overview](#overview)
2. [Configuration](#configuration)
3. [Metrics](#metrics)
4. [Structured Logging](#structured-logging)
5. [Lifecycle Callbacks](#lifecycle-callbacks)
6. [ActiveSupport::Notifications](#activesupportnotifications)
7. [Best Practices](#best-practices)
8. [Examples](#examples)

---

## Overview

ActiveIntelligence provides comprehensive observability features:

- **Metrics**: Track tokens, costs, latency, and success rates
- **Structured Logging**: JSON-formatted logs for all operations
- **Lifecycle Callbacks**: Hook into agent and tool execution
- **ActiveSupport::Notifications**: Rails-compatible instrumentation
- **Error Tracking**: Rich error context and debugging information

---

## Configuration

### Available Settings

```ruby
ActiveIntelligence.configure do |config|
  # Observability settings
  config.settings[:log_level] = :info              # :debug, :info, :warn, :error
  config.settings[:log_api_requests] = false       # Log full API request/response
  config.settings[:log_tool_executions] = true     # Log tool executions
  config.settings[:log_token_usage] = true         # Log token consumption
  config.settings[:structured_logging] = true      # Use JSON structured logging
  config.settings[:enable_notifications] = true    # Enable ActiveSupport::Notifications
end
```

### Logging Levels

| Level | What Gets Logged |
|-------|------------------|
| `:debug` | Everything including API requests/responses, tool executions |
| `:info` | Token usage, API responses, metrics |
| `:warn` | Warnings (truncated responses, etc.) |
| `:error` | Errors only |

---

## Metrics

### Overview

Every agent instance has a `metrics` object that tracks comprehensive statistics.

### Accessing Metrics

```ruby
agent = MyAgent.new
agent.send_message("Hello")
agent.send_message("Tell me a joke")

# Access metrics
puts agent.metrics.to_h
# => {
#      messages: { total: 4, user: 2, agent: 2 },
#      tokens: { total: 523, input: 123, output: 400, cached: 100, cache_hit_rate_percent: 81.3 },
#      api_calls: { total: 2, average_latency_ms: 1234.56, p95_latency_ms: 1500.0, p99_latency_ms: 1500.0 },
#      tool_calls: { total: 3, average_latency_ms: 45.23, by_tool: { "DadJokeTool" => 3 } },
#      errors: { total: 0, by_type: {} },
#      stop_reasons: { "end_turn" => 2 },
#      uptime_seconds: 5.34,
#      estimated_cost_usd: 0.0234
#    }

# Pretty print
puts agent.metrics.to_s
# ActiveIntelligence Metrics
# ===========================
# Messages: 4 (2 user, 2 agent)
# Tokens: 523 total (123 input, 400 output)
# Cached: 100 tokens (81.3% hit rate)
# API Calls: 2 (avg: 1234.56ms, p95: 1500.0ms)
# Tool Calls: 3 (avg: 45.23ms)
# Errors: 0
# Estimated Cost: $0.0234
# Uptime: 5.34s
```

### Available Metrics

#### Message Metrics
- `total_messages` - Total messages sent (user + agent)
- `total_user_messages` - User messages sent
- `total_agent_messages` - Agent responses received

#### Token Metrics
- `total_tokens` - All tokens used
- `total_input_tokens` - Input tokens sent to API
- `total_output_tokens` - Output tokens from API
- `cached_tokens_saved` - Tokens saved via prompt caching
- `cache_hit_rate` - Percentage of tokens served from cache

#### API Call Metrics
- `total_api_calls` - Number of API calls made
- `average_api_latency` - Average API response time (ms)
- `p95_api_latency` - 95th percentile latency
- `p99_api_latency` - 99th percentile latency

#### Tool Metrics
- `total_tool_calls` - Number of tool executions
- `average_tool_latency` - Average tool execution time (ms)
- `tool_executions` - Hash of tool names → execution counts

#### Error Metrics
- `total_errors` - Total errors encountered
- `error_types` - Hash of error types → counts

#### Cost Metrics
- `estimated_cost_usd(model)` - Estimated cost based on token usage
  - Supports: `claude-3-opus`, `claude-3-sonnet`, `claude-3-haiku`
  - Accounts for prompt caching discounts

---

## Structured Logging

### Log Format

When `structured_logging: true`, all logs are JSON-formatted:

```json
{
  "timestamp": "2024-11-15T10:30:45Z",
  "event": "api_response",
  "provider": "claude",
  "model": "claude-3-opus-20240229",
  "duration_ms": 1234.56,
  "usage": {
    "input_tokens": 123,
    "output_tokens": 400,
    "total_tokens": 523,
    "cache_read_input_tokens": 100
  },
  "stop_reason": "end_turn",
  "tool_calls_count": 0
}
```

### Event Types

#### Agent Events
- `message` - User message sent
- `tool_call` - Tool execution

#### API Events
- `api_request` - API request sent
- `api_response` - API response received
- `api_request_streaming` - Streaming request
- `api_response_streaming` - Streaming response complete
- `api_error` - API error

#### Tool Events
- `tool_execution_start` - Tool about to execute
- `tool_execution_success` - Tool completed successfully
- `tool_execution_error` - Tool failed

### Custom Logging

```ruby
# Use structured logging in your code
ActiveIntelligence::Config.log(:info, {
  event: 'custom_event',
  data: { foo: 'bar' }
})
```

---

## Lifecycle Callbacks

### Overview

Callbacks allow you to hook into the agent execution lifecycle without modifying core code.

### Available Callbacks

- `before_message` - Called before sending a message
- `after_message` - Called after receiving a response
- `before_tool_call` - Called before executing a tool
- `after_tool_call` - Called after tool execution
- `on_error` - Called when an error occurs

### Registering Callbacks

```ruby
class MyAgent < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity "You are a helpful assistant"

  # Before sending a message
  before_message do |data|
    puts "About to send: #{data[:content]}"
    # Track in APM
    NewRelic::Agent.record_metric('CustomMetrics/MessageSent', 1)
  end

  # After receiving a response
  after_message do |data|
    puts "Response: #{data[:response].content}"
    puts "Message count: #{data[:message_count]}"
    puts "Metrics: #{data[:metrics]}"

    # Send to monitoring
    StatsD.gauge('ai.conversation_length', data[:message_count])
  end

  # Before tool execution
  before_tool_call do |data|
    puts "Executing tool: #{data[:tool_name]}"
    puts "Params: #{data[:params]}"
  end

  # After tool execution
  after_tool_call do |data|
    puts "Tool #{data[:tool_name]} took #{data[:duration_ms]}ms"
    puts "Success: #{data[:success]}"

    # Track tool performance
    StatsD.histogram("ai.tool.#{data[:tool_name]}.duration", data[:duration_ms])
  end

  # On error
  on_error do |data|
    puts "Error: #{data[:error].class.name}"
    puts "Context: #{data[:context]}"

    # Send to error tracker
    Sentry.capture_exception(data[:error], extra: data[:context])
  end
end
```

### Callback Data

Each callback receives a hash with relevant data:

#### `before_message`
```ruby
{
  content: "User message",
  options: { ... }
}
```

#### `after_message`
```ruby
{
  content: "User message",
  response: <AgentResponse>,
  message_count: 4,
  metrics: { ... }
}
```

#### `before_tool_call`
```ruby
{
  tool_name: "DadJokeTool",
  params: { query: "cat" }
}
```

#### `after_tool_call`
```ruby
{
  tool_name: "DadJokeTool",
  params: { query: "cat" },
  result: { success: true, data: { ... } },
  duration_ms: 45.23,
  success: true
}
```

#### `on_error`
```ruby
{
  error: <Exception>,
  context: { content: "...", options: { ... } }
}
```

---

## ActiveSupport::Notifications

### Overview

ActiveIntelligence emits `ActiveSupport::Notifications` events for all major operations. This integrates seamlessly with Rails and monitoring tools like Scout, New Relic, and Datadog.

### Enabling

```ruby
ActiveIntelligence.configure do |config|
  config.settings[:enable_notifications] = true
end
```

### Available Events

All events are namespaced under `.activeintelligence`:

- `message.activeintelligence`
- `tool_call.activeintelligence`
- `api_call.activeintelligence`
- `api_call_streaming.activeintelligence`
- `tool_error.activeintelligence`

### Subscribing to Events

```ruby
# Subscribe to specific events
ActiveSupport::Notifications.subscribe('message.activeintelligence') do |name, start, finish, id, payload|
  duration = (finish - start) * 1000  # Convert to ms

  puts "Message processed in #{duration}ms"
  puts "Response: #{payload[:response]}"
  puts "Metrics: #{payload[:metrics]}"

  # Send to monitoring
  StatsD.histogram('ai.message.duration', duration)
  StatsD.increment('ai.message.count')
end

# Subscribe to all ActiveIntelligence events
ActiveSupport::Notifications.subscribe(/\.activeintelligence$/) do |name, start, finish, id, payload|
  event_type = name.split('.').first
  duration = (finish - start) * 1000

  Rails.logger.info({
    event: event_type,
    duration_ms: duration,
    payload: payload
  }.to_json)
end
```

### Event Payloads

#### `message.activeintelligence`
```ruby
{
  content: "User message",
  options: { ... },
  response: <AgentResponse>,
  message_count: 4,
  metrics: { ... }
}
```

#### `api_call.activeintelligence`
```ruby
{
  provider: :claude,
  model: "claude-3-opus-20240229",
  message_count: 2,
  duration_ms: 1234.56,
  usage: { ... },
  stop_reason: "end_turn",
  tool_calls_count: 0
}
```

#### `tool_call.activeintelligence`
```ruby
{
  tool_name: "DadJokeTool",
  params: { ... },
  result: { ... },
  duration_ms: 45.23,
  success: true
}
```

### Integration with APM Tools

#### New Relic

```ruby
ActiveSupport::Notifications.subscribe('api_call.activeintelligence') do |name, start, finish, id, payload|
  NewRelic::Agent.record_metric('Custom/AI/APICall', (finish - start) * 1000)
  NewRelic::Agent.record_metric('Custom/AI/Tokens', payload[:usage][:total_tokens]) if payload[:usage]
end
```

#### Datadog

```ruby
ActiveSupport::Notifications.subscribe(/\.activeintelligence$/) do |name, start, finish, id, payload|
  event_type = name.split('.').first
  duration = finish - start

  Datadog::Statsd.new.histogram("activeintelligence.#{event_type}.duration", duration)
end
```

#### Scout APM

Scout automatically instruments `ActiveSupport::Notifications`, so events will appear in your Scout dashboard.

---

## Best Practices

### 1. Monitor Token Usage and Costs

```ruby
class MyAgent < ActiveIntelligence::Agent
  after_message do |data|
    metrics = data[:metrics]

    # Alert if costs are high
    if metrics[:tokens][:total] > 10_000
      AlertService.notify("High token usage: #{metrics[:tokens][:total]} tokens")
    end

    # Track costs over time
    MetricsService.record('ai.cost', metrics[:estimated_cost_usd])
  end
end
```

### 2. Track Tool Performance

```ruby
class MyAgent < ActiveIntelligence::Agent
  after_tool_call do |data|
    # Alert on slow tools
    if data[:duration_ms] > 1000
      AlertService.notify("Slow tool: #{data[:tool_name]} took #{data[:duration_ms]}ms")
    end

    # Track success rates
    status = data[:success] ? 'success' : 'failure'
    StatsD.increment("ai.tool.#{data[:tool_name]}.#{status}")
  end
end
```

### 3. Error Tracking

```ruby
class MyAgent < ActiveIntelligence::Agent
  on_error do |data|
    # Send to error tracker with rich context
    Sentry.capture_exception(data[:error], extra: {
      context: data[:context],
      agent_class: self.class.name,
      conversation_length: @messages.length
    })
  end
end
```

### 4. Performance Monitoring

```ruby
# Track P95 latency
ActiveSupport::Notifications.subscribe('api_call.activeintelligence') do |name, start, finish, id, payload|
  duration = (finish - start) * 1000

  # Store for analysis
  Redis.current.lpush('ai:api_latencies', duration)
  Redis.current.ltrim('ai:api_latencies', 0, 999)  # Keep last 1000

  # Alert on slow responses
  if duration > 5000
    PagerDuty.trigger("Slow AI response: #{duration}ms")
  end
end
```

### 5. Cache Hit Monitoring

```ruby
class MyAgent < ActiveIntelligence::Agent
  after_message do |data|
    cache_hit_rate = data[:metrics][:tokens][:cache_hit_rate_percent]

    # Alert if cache not working
    if cache_hit_rate < 50 && @messages.length > 5
      AlertService.notify("Low cache hit rate: #{cache_hit_rate}%")
    end
  end
end
```

---

## Examples

### Complete Monitoring Setup

```ruby
class ProductionAgent < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity "You are a helpful assistant"
  tool MyTool

  # Track all messages
  before_message do |data|
    RequestStore.store[:ai_start_time] = Time.now
  end

  after_message do |data|
    duration = Time.now - RequestStore.store[:ai_start_time]
    metrics = data[:metrics]

    # Log to application logs
    Rails.logger.info({
      event: 'ai_message_complete',
      duration_seconds: duration,
      message_count: data[:message_count],
      tokens: metrics[:tokens],
      cost: metrics[:estimated_cost_usd]
    }.to_json)

    # Send to monitoring
    StatsD.histogram('ai.message.duration', duration * 1000)
    StatsD.gauge('ai.conversation_length', data[:message_count])
    StatsD.gauge('ai.tokens_used', metrics[:tokens][:total])
    StatsD.gauge('ai.cache_hit_rate', metrics[:tokens][:cache_hit_rate_percent])
  end

  # Track tool performance
  after_tool_call do |data|
    StatsD.histogram("ai.tool.#{data[:tool_name]}.duration", data[:duration_ms])
    StatsD.increment("ai.tool.#{data[:tool_name]}.#{data[:success] ? 'success' : 'failure'}")
  end

  # Error tracking
  on_error do |data|
    Sentry.capture_exception(data[:error], extra: {
      context: data[:context],
      agent_class: self.class.name,
      metrics: @metrics.to_h
    })
  end
end

# Subscribe to all events for centralized logging
ActiveSupport::Notifications.subscribe(/\.activeintelligence$/) do |name, start, finish, id, payload|
  LogStash.log({
    event_type: name,
    duration_ms: (finish - start) * 1000,
    payload: payload,
    timestamp: Time.now.iso8601
  })
end
```

### Custom Metrics Dashboard

```ruby
# Expose metrics via API endpoint
class MetricsController < ApplicationController
  def show
    agent = CurrentAgent.instance

    render json: {
      uptime_seconds: agent.metrics.uptime_seconds,
      messages: agent.metrics.to_h[:messages],
      tokens: agent.metrics.to_h[:tokens],
      api_calls: agent.metrics.to_h[:api_calls],
      tool_calls: agent.metrics.to_h[:tool_calls],
      errors: agent.metrics.to_h[:errors],
      estimated_cost: agent.metrics.estimated_cost_usd
    }
  end
end
```

### Debug Mode

```ruby
# Enable verbose logging for debugging
ActiveIntelligence.configure do |config|
  config.settings[:log_level] = :debug
  config.settings[:log_api_requests] = true
  config.settings[:log_tool_executions] = true
  config.settings[:log_token_usage] = true
end

# All API requests/responses and tool executions will be logged
```

---

## Troubleshooting

### High Token Usage

```ruby
# Check metrics to identify the issue
puts agent.metrics.to_h[:tokens]
# => { total: 50000, input: 45000, output: 5000, cached: 0, cache_hit_rate_percent: 0.0 }

# Low cache hit rate? Check if prompt caching is enabled
agent = MyAgent.new(options: { enable_prompt_caching: true })

# Long conversations? Consider truncating history
if agent.metrics.total_messages > 20
  # Implement conversation summarization or truncation
end
```

### Slow Responses

```ruby
# Check P95 latency
puts agent.metrics.p95_api_latency
# => 5000.0  # 5 seconds - too slow!

# Check tool performance
puts agent.metrics.to_h[:tool_calls][:by_tool]
# => { "SlowTool" => 10 }

puts agent.metrics.average_tool_latency
# => 4500.0  # Tool is the bottleneck!
```

### Error Tracking

```ruby
# Check error counts
puts agent.metrics.to_h[:errors]
# => { total: 5, by_type: { "ToolError" => 3, "ApiError" => 2 } }

# Errors are automatically logged with full context
# Check logs for detailed error information
```

---

## Additional Resources

- [CLAUDE.md](CLAUDE.md) - Developer cheat sheet
- [README.md](README.md) - Getting started guide
- [Anthropic Documentation](https://docs.anthropic.com/) - Claude API docs

---

**Last Updated**: 2024-11-15
**Version**: 0.0.1
