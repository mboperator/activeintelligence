# ActiveIntelligence Streaming Format

## Overview

ActiveIntelligence uses **Server-Sent Events (SSE)** as the common streaming format across all API clients. This allows the framework to support multiple LLM providers (Claude, OpenAI, Gemini, etc.) while maintaining a consistent interface.

## Common Format Specification

All API clients (`ClaudeClient`, `OpenAIClient`, etc.) must yield **SSE-formatted strings** when streaming:

### Text Chunks

```ruby
"data: #{text}\n\n"
```

**Example:**
```ruby
yield "data: Hello\n\n"
yield "data:  world\n\n"
```

### Custom Events

**Frontend Tool Request:**
```ruby
"event: frontend_tool_request\ndata: #{json_data}\n\n"
```

**Example:**
```ruby
yield "event: frontend_tool_request\n"
yield "data: #{JSON.generate({
  status: 'awaiting_tool_results',
  pending_tools: [...],
  conversation_id: 123
})}\n\n"
```

**Backend Tool Result:**
```ruby
"event: tool_result\ndata: #{json_data}\n\n"
```

**Example:**
```ruby
yield "event: tool_result\n"
yield "data: #{JSON.generate({
  tool_name: 'bible_lookup',
  tool_use_id: 'toolu_123',
  content: '{"reference": "Psalm 23", ...}'
})}\n\n"
```

### Stream Completion

```ruby
"data: [DONE]\n\n"
```

## Architecture Flow

```
┌──────────────────┐
│  API Client      │  Parses provider-specific streaming format
│  (ClaudeClient)  │  ↓
└──────────────────┘  Yields SSE-formatted strings
         ↓
┌──────────────────┐
│  Agent           │  Passes through SSE chunks
│  (call_streaming)│  May add additional SSE events
└──────────────────┘  (e.g., frontend_tool_request)
         ↓
┌──────────────────┐
│  Controller      │  Writes chunks directly to stream
│  (streaming)     │  response.stream.write chunk
└──────────────────┘
         ↓
┌──────────────────┐
│  Browser         │  EventSource API parses SSE
│  (JavaScript)    │  Extracts data from events
└──────────────────┘
```

## Implementation Guidelines

### For API Client Implementers

When implementing a new API client (e.g., `OpenAIClient`), follow this pattern:

```ruby
def call_streaming(messages, system_prompt, options = {}, &block)
  # 1. Make streaming request to provider API
  # 2. Parse provider-specific streaming format
  # 3. Yield SSE-formatted strings

  provider_stream.each do |provider_chunk|
    # Parse provider chunk
    text = extract_text(provider_chunk)

    # Yield SSE format
    yield "data: #{text}\n\n" if block_given?

    # Accumulate full response for return value
    full_response << text
  end

  # Return normalized response
  {
    content: full_response,
    tool_calls: [...],
    stop_reason: ...
  }
end
```

### Key Requirements

1. **Always yield SSE format**: Even if the provider uses a different streaming protocol
2. **Text only**: Only yield user-visible text chunks (not thinking/metadata)
3. **No double-wrapping**: Don't add `data: ` prefix if it's already present
4. **Proper line endings**: Always end with `\n\n` for SSE compatibility
5. **Handle provider events**: Map provider-specific events to SSE events when needed

### Example: Claude Client

```ruby
# Claude sends SSE already, but we extract and re-format
if json_data["type"] == "content_block_delta" &&
   json_data["delta"]["type"] == "text_delta"
  text = json_data["delta"]["text"]

  # Accumulate for return value
  full_response << text

  # Yield SSE-formatted chunk
  yield "data: #{text}\n\n" if block_given?
end
```

### Example: Future OpenAI Client

```ruby
# OpenAI uses different format, convert to SSE
stream.each do |chunk|
  if chunk.choices[0].delta.content
    text = chunk.choices[0].delta.content

    # Accumulate for return value
    full_response << text

    # Convert to SSE format
    yield "data: #{text}\n\n" if block_given?
  end
end
```

## Benefits of This Approach

✅ **Provider-agnostic**: Agent and controller don't need provider-specific code
✅ **Browser-compatible**: SSE is natively supported by browsers via EventSource API
✅ **Consistent**: Same format across all providers
✅ **Extensible**: Easy to add custom events (like frontend tool requests)
✅ **Standard**: SSE is a W3C standard with wide support

## Frontend Parsing

The JavaScript frontend expects this SSE format:

```javascript
const lines = buffer.split('\n');
let currentEvent = null;

for (const line of lines) {
  if (line.startsWith('event: ')) {
    currentEvent = line.substring(7);
  } else if (line.startsWith('data: ')) {
    const data = line.substring(6);

    if (data === '[DONE]') {
      continue;
    }

    if (currentEvent === 'frontend_tool_request') {
      // Handle frontend tool request
      const toolRequest = JSON.parse(data);
      await executeFrontendTool(toolRequest);
    } else if (currentEvent === 'tool_result') {
      // Display backend tool result in separate message box
      const toolResult = JSON.parse(data);
      displayToolMessage(toolResult.tool_name, toolResult.content);
    } else {
      // Regular text chunk - append to assistant message
      assistantContent.textContent += data;
    }
  } else if (line === '') {
    currentEvent = null; // Reset on empty line
  }
}
```

## SSE Format Reference

From the [W3C Server-Sent Events specification](https://html.spec.whatwg.org/multipage/server-sent-events.html):

- **Lines starting with `data:`** contain the event data
- **Lines starting with `event:`** set the event type
- **Empty line (`\n\n`)** dispatches the event
- **Default event type** is `message` if not specified

**Example multi-line data:**
```
data: First line
data: Second line

```

**Example custom event:**
```
event: frontend_tool_request
data: {"status": "pending"}

```

## Testing

When writing tests for API clients, expect SSE format:

```ruby
chunks = []
client.call_streaming(messages, system_prompt) { |chunk| chunks << chunk }

expect(chunks).to eq([
  "data: Hello\n\n",
  "data:  world\n\n"
])
```

## Version History

- **v0.0.1** (2025-11-15): Initial SSE format specification

---

**Last Updated**: November 15, 2025
**Specification Version**: 1.0
**Status**: Active
