---
title: Create an Agent
description: Build and run a functional agent with tools, an identity, and a conversation loop.
tags: [agent, quickstart, how-to]
---

## Prerequisites

- ActiveIntelligence installed and `ANTHROPIC_API_KEY` set (see [Setup](setup))

## 1. Define the Agent

Create a subclass of `ActiveIntelligence::Agent` and configure it with the DSL:

```ruby
require "activeintelligence"

class CustomerSupportAgent < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity <<~PROMPT
    You are a friendly customer support agent for Acme Corp.
    Help users with billing questions, account issues, and product questions.
    If you need to look up order details, use the get_order tool.
  PROMPT

  tool GetOrderTool
end
```

The `identity` becomes the system prompt. Write it as a clear role description — Claude uses it to determine when and how to call your tools.

## 2. Define a Tool

```ruby
class GetOrderTool < ActiveIntelligence::Tool
  name "get_order"
  description "Look up an order by ID and return its status and details."

  param :order_id, type: String, required: true, description: "The order ID (e.g. ORD-12345)"

  def execute(params)
    order = Order.find_by(id: params[:order_id])
    return error_response("Order not found", details: { order_id: params[:order_id] }) unless order

    success_response({
      id:     order.id,
      status: order.status,
      total:  order.total_cents / 100.0,
      items:  order.items.map { |i| { name: i.name, qty: i.quantity } }
    })
  end
end
```

Register it on the agent with `tool GetOrderTool`. See [Create a Tool](create_a_tool) for full DSL docs.

## 3. Instantiate and Run

```ruby
agent = CustomerSupportAgent.new

# Single message
puts agent.send_message("What is the status of order ORD-99001?")

# Interactive loop
loop do
  print "You: "
  input = gets.chomp
  break if input == "quit"

  response = agent.send_message(input)
  puts "Agent: #{response}"
end
```

Context is preserved across calls — the same `agent` instance maintains conversation history, so follow-up questions work naturally.

## 4. Streaming Responses

For real-time output, pass `stream: true` with a block:

```ruby
print "Agent: "
agent.send_message("Summarize the last 5 orders.", stream: true) do |chunk|
  print chunk
  $stdout.flush
end
puts  # newline after stream ends
```

See [Streaming](streaming) for more detail.

## 5. Pass Context to Tools

If your tools need access to the current user or other request-level data, pass it via `context:`:

```ruby
agent = CustomerSupportAgent.new(context: { current_user: current_user })
```

Tools access it via `context_field`:

```ruby
class GetOrderTool < ActiveIntelligence::Tool
  context_field :current_user, required: true

  def execute(params)
    order = current_user.orders.find_by(id: params[:order_id])
    # ...
  end
end
```

## 6. Observability

Add callbacks to log, trace, or monitor:

```ruby
class CustomerSupportAgent < ActiveIntelligence::Agent
  # ...

  on_turn_start  { |turn|      Rails.logger.info "Turn: #{turn.id}" }
  on_tool_end    { |execution| Rails.logger.info "Tool #{execution.name}: #{execution.duration.round(2)}s" }
  on_error       { |ctx|       Sentry.capture_exception(ctx.error) }
end
```

See [Callbacks](../key_concepts/callbacks) for all 16 hooks.

## Full Example

Working example at `bin/dad_joke_agent.rb`:

```ruby
require_relative "../lib/activeintelligence"
require_relative "../lib/dad_joke_tool"

class JokeAssistant < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity "You are a friendly assistant who loves dad jokes. Use the get_dad_joke tool to fetch jokes."
  tool ActiveIntelligence::DadJokeTool
end

agent = JokeAssistant.new

loop do
  print "You: "
  input = gets.chomp
  break if %w[quit exit].include?(input.downcase)
  puts "Agent: #{agent.send_message(input)}"
end
```
