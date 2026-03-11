---
title: OpenAI
description: Use OpenAI's GPT models as the LLM provider instead of Claude.
tags: [openai, provider, configuration]
---

## Prerequisites

- An [OpenAI API key](https://platform.openai.com)
- `OPENAI_API_KEY` environment variable set

## Switch to OpenAI

Change the `model` DSL call to `:openai`:

```ruby
class MyAgent < ActiveIntelligence::Agent
  model :openai
  memory :in_memory
  identity "You are a helpful assistant."
  tool MyTool
end
```

The agent automatically uses `OpenAIClient` instead of `ClaudeClient`. Tools, streaming, callbacks, and memory strategies work identically.

Source: `agent.rb:488-497`

## API Key

```bash
export OPENAI_API_KEY="sk-..."
```

The `OpenAIClient` reads `ENV["OPENAI_API_KEY"]` at initialization.

Source: `api_clients/openai_client.rb:7-14`

## Model Selection

Override the model per agent or globally:

```ruby
# Per instantiation
agent = MyAgent.new(options: { model: "gpt-4o" })

# Global default (in initializer)
ActiveIntelligence.configure do |config|
  config.settings[:openai] ||= {}
  config.settings[:openai][:model] = "gpt-4o-mini"
end
```

## Differences from Claude

| Feature | Claude | OpenAI |
|---------|--------|--------|
| Prompt caching | Supported (80-90% savings) | Not supported |
| Extended thinking | Supported | Not supported |
| Tool calling | Native support | Function calling format |
| Streaming | SSE with event types | SSE with delta format |
| System prompt | Separate `system` array field | First message with `role: "system"` |

The `OpenAIClient#format_messages` (`openai_client.rb:57-68`) prepends the system prompt as the first message, matching OpenAI's expected format.

Tool schemas are converted from ActiveIntelligence's internal format to OpenAI's `function` tool format in `build_request_params` (`openai_client.rb:109-135`).

## Response Normalization

`OpenAIClient#normalize_response` (`openai_client.rb:154-191`) converts OpenAI's response format into the same internal format that `ClaudeClient` produces. This means the agent's message handling and tool loop code is identical regardless of which provider is used.

## Truncation Warning

Like with Claude, the client logs a warning if the response was cut off due to `max_tokens`:

```
WARN: Response may be truncated - finish_reason: length
```

Increase `max_tokens` via the global config if you hit this.
