---
title: Message Flow
description: The end-to-end path from a user calling send_message to receiving the final response.
tags: [message-flow, workflow, architecture]
---

## Prerequisites

- Familiarity with [Agent](../key_concepts/agent), [Messages](../key_concepts/messages), and [Tool](../key_concepts/tool)

## Overview

Every call to `agent.send_message(text)` goes through a fixed sequence: add to history, call the API, handle the response (text or tool calls), and return the final answer.

```mermaid
sequenceDiagram
    participant U as User Code
    participant A as Agent
    participant H as History (@messages)
    participant API as ClaudeClient
    participant T as Tool

    U->>A: send_message("What's the weather?")
    A->>H: add UserMessage
    A->>A: trigger on_turn_start
    A->>API: call(formatted_messages, system_prompt)
    API-->>A: {content: "", tool_calls: [{name: "get_weather", ...}]}
    A->>H: add AgentResponse(tool_calls)
    A->>A: process_tool_calls
    A->>H: add ToolResponse(pending)
    A->>T: execute({city: "Paris"})
    T-->>A: success_response({temp: "15°C"})
    A->>H: complete! ToolResponse
    A->>API: call(formatted_messages_with_tool_result)
    API-->>A: {content: "The weather in Paris is 15°C."}
    A->>H: add AgentResponse(content)
    A->>A: trigger on_turn_end
    A-->>U: "The weather in Paris is 15°C."

    click A href "#" "lib/activeintelligence/agent.rb:84-126"
    click API href "#" "lib/activeintelligence/api_clients/claude_client.rb:18-30"
    click T href "#" "lib/activeintelligence/tool.rb:177-194"
    click H href "#" "lib/activeintelligence/messages.rb"
```

## Step-by-Step

### 1. `send_message` entry point

`agent.rb:84-126` — Dispatches to `send_message_static` or `send_message_streaming`. Both paths:
- Add a `UserMessage` to `@messages`
- Fire `on_turn_start`
- Delegate to the appropriate API call method

### 2. Format messages for the API

`claude_client.rb:59-68` — The API client converts `@messages` to the provider's expected format:
- `UserMessage` → `{ role: "user", content: "..." }`
- `AgentResponse` → `{ role: "assistant", content: [...] }`
- `ToolResponse` (complete only) → `{ role: "user", content: [{ type: "tool_result", ... }] }`

Pending `ToolResponse` objects are **filtered out** at this step.

### 3. API call

`claude_client.rb:18-30` — Sends the HTTP request to `https://api.anthropic.com/v1/messages` with:
- `model`, `max_tokens`, `system` (cached)
- `messages` (formatted history)
- `tools` (JSON schemas from registered tools, cached)
- Fires `on_response_start`

### 4. Parse the response

`claude_client.rb:168-233` — Extracts from the API response:
- `content` — the text blocks
- `tool_calls` — normalized array of `{id, name, input}` hashes
- `stop_reason` — `"end_turn"`, `"tool_use"`, `"max_tokens"`, etc.
- `usage` — input/output/cache token counts

### 5. Add AgentResponse to history

The agent creates an `AgentResponse` with the content and tool_calls, adds it to `@messages`, and fires `on_message_added`.

### 6. Check stop reason

- `stop_reason == "tool_use"` → enter `process_tool_calls` (see [Tool Calling Loop](tool_calling_loop))
- `stop_reason == "end_turn"` → return the response text
- `stop_reason == "max_tokens"` → return truncated response with a log warning

### 7. Return response

After all tool loops complete, `send_message` returns the final text string. The `on_turn_end` callback fires with accumulated usage data.

## Message History After a Turn

```
Before:  []
After send_message (no tools):
  [UserMessage, AgentResponse]

After send_message (one tool):
  [UserMessage, AgentResponse(tool_calls), ToolResponse(complete), AgentResponse]

After send_message (two tools in one turn):
  [UserMessage, AgentResponse(tool_calls×2), ToolResponse, ToolResponse, AgentResponse]
```

The history grows with each turn. All messages are included in subsequent API calls to maintain context.

## System Prompt Construction

`agent.rb:499-514` — `build_system_prompt` combines:
1. The `identity` string
2. A description of all registered tools and their parameters

This becomes the `system` field in the API request. With prompt caching enabled, it's marked `cache_control: { type: "ephemeral" }` to avoid re-tokenizing it on every call.
