---
title: Streaming
description: Receive Claude's response in real time using Server-Sent Events, including tool calls and extended thinking.
tags: [streaming, sse, real-time]
---

## Prerequisites

- An agent defined and configured (see [Create an Agent](create_an_agent))

## Basic Streaming

Pass `stream: true` and a block to `send_message`. The block receives text chunks as they arrive:

```ruby
agent.send_message("Write a short story about a robot.", stream: true) do |chunk|
  print chunk
  $stdout.flush
end
puts  # newline after stream ends
```

The block is called with each text fragment. Tool calls, thinking blocks, and orchestration happen transparently — your block only receives the final text Claude outputs to the user.

Source: `agent.rb:368-376`

## Streaming with Tools

Tool calling works identically in streaming mode. When Claude requests a tool, the agent:
1. Accumulates the tool input from streamed `input_json_delta` events
2. Executes the tool
3. Streams Claude's response to the tool result

Your block still only sees the user-facing text chunks:

```ruby
agent = WeatherAgent.new

agent.send_message("What's the weather in Tokyo and Paris?", stream: true) do |chunk|
  print chunk  # receives text before tools, between tool results, and after
end
```

See [Streaming Pipeline](../workflows/streaming_pipeline) for the full SSE parsing flow.

## Collecting the Full Response

If you need the complete text after streaming:

```ruby
buffer = +""  # unfrozen string for appending

agent.send_message("Summarize this document.", stream: true) do |chunk|
  buffer << chunk
  print chunk
end

puts "\n\nFull response: #{buffer}"
```

## Extended Thinking

When Claude uses extended thinking, thinking blocks stream separately before the visible response. The agent fires `on_thinking_start` and `on_thinking_end` callbacks but does **not** pass thinking content to your streaming block — it's internal to Claude's reasoning.

To observe thinking content, use callbacks:

```ruby
class MyAgent < ActiveIntelligence::Agent
  on_thinking_end do |thinking|
    Rails.logger.debug "Thinking: #{thinking.content}"
  end
end
```

## Streaming in Rails

In a Rails controller, use `ActionController::Live` to stream over HTTP:

```ruby
class ChatController < ApplicationController
  include ActionController::Live

  def stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"

    agent = MyAgent.new(context: { current_user: current_user })

    agent.send_message(params[:message], stream: true) do |chunk|
      response.stream.write("data: #{chunk.to_json}\n\n")
    end

  ensure
    response.stream.close
  end
end
```

On the client side, consume with `EventSource` or `fetch` with a streaming reader.

## Streaming with Callbacks

Full observability is available in streaming mode. The `on_response_chunk` callback fires for every chunk:

```ruby
class MyAgent < ActiveIntelligence::Agent
  on_response_chunk do |chunk|
    # chunk.content, chunk.index, chunk.response_id
    StatsD.increment("stream.chunk")
  end

  on_response_end do |response|
    Rails.logger.info "Stream complete. Tokens: #{response.usage.total_tokens}"
  end
end
```

## Error Handling in Streaming

If an error occurs mid-stream, the agent fires `on_error` and raises after the stream ends. Wrap in a `begin/rescue`:

```ruby
begin
  agent.send_message("...", stream: true) { |c| print c }
rescue ActiveIntelligence::ApiError => e
  puts "\nStream failed: #{e.message}"
end
```
