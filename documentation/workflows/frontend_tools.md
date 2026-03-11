---
title: Frontend Tools
description: How to defer tool execution to the client, pause the agent, and resume it with results.
tags: [frontend-tools, deferral, workflow, client-side]
---

## Prerequisites

- Read [Tool Calling Loop](tool_calling_loop)
- Familiarity with [Memory strategies](../key_concepts/memory)

## Overview

Not every tool can run on the server. Frontend tools let Claude request actions that only the client can perform — file picker dialogs, camera access, browser APIs, user confirmation prompts. The agent pauses when it encounters one, returns a description of what needs to happen, and resumes when the client provides the result.

```mermaid
sequenceDiagram
    participant CLIENT as Client (browser/mobile)
    participant AGENT as Agent
    participant CLAUDE as Claude API

    CLIENT->>AGENT: send_message("Please open a file")
    AGENT->>CLAUDE: API call
    CLAUDE-->>AGENT: {tool_calls: [{name: "open_file", ...}]}
    AGENT->>AGENT: partition_tool_calls → frontend tool found
    AGENT->>AGENT: create ToolResponse(pending)
    AGENT->>AGENT: state = awaiting_tool_results
    AGENT-->>CLIENT: {pending_tools: [{tool_use_id, name, params}]}

    Note over CLIENT: Client executes "open_file"<br/>user picks a file

    CLIENT->>AGENT: continue_with_tool_results({tool_use_id: ..., result: ...})
    AGENT->>AGENT: complete! ToolResponse with result
    AGENT->>CLAUDE: API call (with tool result)
    CLAUDE-->>AGENT: {content: "File opened: report.pdf"}
    AGENT-->>CLIENT: "File opened: report.pdf"

    click AGENT href "#" "lib/activeintelligence/agent.rb:129-215"
```

## Defining a Frontend Tool

```ruby
class OpenFileTool < ActiveIntelligence::Tool
  name "open_file"
  description "Open a file picker dialog on the user's device and return the selected file's contents."
  execution_context :frontend

  param :accept, type: String, required: false,
    description: "Accepted file types, e.g. '.pdf,.docx'"

  def execute(params)
    # This method is never called on the backend.
    # Required to satisfy the base class interface.
    success_response({})
  end
end
```

Source: `tool.rb:63-66`

## Sending the Initial Message

```ruby
agent = MyAgent.new

result = agent.send_message("Please open a PDF file for me.")
# result may be a string describing the pending action, or a hash with pending tool info

if agent.paused_for_frontend?
  # The client needs to do something before the conversation can continue
  pending = result  # contains tool name, parameters, tool_use_id
end
```

`paused_for_frontend?` (`agent.rb:218-219`) returns `true` when `@state == STATES[:awaiting_tool_results]`.

## The Pending Response Format

When the agent pauses, `build_pending_tools_response` (`agent.rb:739-761`) returns a hash describing what the client must execute:

```json
{
  "status": "awaiting_tool_results",
  "pending_tools": [
    {
      "tool_use_id": "toolu_01AbCd...",
      "name": "open_file",
      "parameters": { "accept": ".pdf" }
    }
  ]
}
```

The client uses `tool_use_id` to correlate the result when resuming.

## Resuming with Results

After the client executes the tool, call `continue_with_tool_results`:

```ruby
# Single tool result
agent.continue_with_tool_results({
  "tool_use_id" => "toolu_01AbCd...",
  "result"      => { "filename" => "report.pdf", "contents" => "..." }
})

# Multiple tool results (if multiple frontend tools were pending)
agent.continue_with_tool_results([
  { "tool_use_id" => "toolu_01...", "result" => "..." },
  { "tool_use_id" => "toolu_02...", "result" => "..." }
])
```

`continue_with_tool_results` (`agent.rb:129-215`):
1. Validates that state is `awaiting_tool_results`
2. Finds each pending `ToolResponse` by `tool_use_id`
3. Calls `complete!` on each with the provided result
4. Resumes the tool-calling loop

## Streaming Resume

```ruby
agent.continue_with_tool_results(results, stream: true) do |chunk|
  print chunk
end
```

## Persisting State Across Requests (Rails)

With `memory: :active_record`, the agent's state persists between HTTP requests:

```ruby
# Request 1: User sends message
agent = conversation.agent
result = agent.send_message(params[:message])

if agent.paused_for_frontend?
  render json: { pending_tools: result[:pending_tools], conversation_id: conversation.id }
  return
end

render json: { response: result }
```

```ruby
# Request 2: Client submits tool results
agent = conversation.agent  # state = "awaiting_tool_results" loaded from DB
result = agent.continue_with_tool_results(params[:tool_results])
render json: { response: result }
```

The `awaiting_tool_results` state is stored in `conversations.agent_state`. The pending `ToolResponse` records remain in the `messages` table with `status: "pending"` until `continue_with_tool_results` is called.

## Mixed Backend/Frontend Turns

A single Claude response can request both backend and frontend tools. The agent:
1. Executes all backend tools immediately
2. Pauses for frontend tools

The client only needs to provide results for the frontend tools — backend results are already complete.
