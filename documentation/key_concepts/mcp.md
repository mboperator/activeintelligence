---
title: MCP Server
description: A Rails controller base class for exposing ActiveIntelligence tools as a Model Context Protocol (MCP) server.
tags: [mcp, rails, model-context-protocol, server]
---

## Overview

`ActiveIntelligence::MCP::BaseController` is a Rails `ActionController::API` subclass that implements the [Model Context Protocol](https://modelcontextprotocol.io) (MCP) specification. Mount it to expose your tools to any MCP-compatible client — including Claude Desktop, other AI agents, or your own applications.

MCP uses JSON-RPC 2.0 over HTTP. The controller handles protocol negotiation, session initialization, tool listing, and tool invocation.

Source: `mcp/base_controller.rb`

## Basic Setup

```ruby
# app/controllers/my_mcp_controller.rb
class MyMcpController < ActiveIntelligence::MCP::BaseController
  tools WeatherTool, SearchTool, CalendarTool

  server_name "my-app-mcp"
  server_version "1.0.0"
end

# config/routes.rb
post "/mcp", to: "my_mcp#handle"
```

That's the minimal setup. The controller handles all MCP protocol details automatically.

## DSL Reference

| Method | Purpose | Source |
|--------|---------|--------|
| `tools *tool_classes` | Register tools to expose | `base_controller.rb:75-77` |
| `server_name "name"` | Set MCP server name | `base_controller.rb:80-82` |
| `server_version "1.0"` | Set MCP server version | `base_controller.rb:84-86` |

## Protocol Flow

```mermaid
sequenceDiagram
    participant CLIENT as MCP Client
    participant CTRL as BaseController
    participant TOOL as Tool

    CLIENT->>CTRL: POST /mcp {method: "initialize"}
    CTRL-->>CLIENT: {capabilities, serverInfo, protocolVersion}

    CLIENT->>CTRL: POST /mcp {method: "notifications/initialized"}
    CTRL-->>CLIENT: (no response)

    CLIENT->>CTRL: POST /mcp {method: "tools/list"}
    CTRL-->>CLIENT: {tools: [{name, description, inputSchema}]}

    CLIENT->>CTRL: POST /mcp {method: "tools/call", params: {name, arguments}}
    CTRL->>TOOL: call(arguments)
    TOOL-->>CTRL: success_response / error_response
    CTRL-->>CLIENT: {content: [{type: "text", text: "..."}]}

    click CTRL href "#" "lib/activeintelligence/mcp/base_controller.rb"
    click TOOL href "#" "lib/activeintelligence/tool.rb"
```

**Protocol version:** `2025-11-25` (configured at `base_controller.rb:8`)

## Override Points

The controller provides protected methods you can override to customize behavior:

### Authentication

```ruby
def authenticate_mcp_request
  token = request.headers["Authorization"]&.split(" ")&.last
  head :unauthorized unless valid_token?(token)
end
```

Source: `base_controller.rb:191-193`

### Context

Tools receive context from the agent. In MCP, provide context by overriding `mcp_context`:

```ruby
def mcp_context
  { current_user: current_user, tenant: current_tenant }
end
```

Source: `base_controller.rb:202-204`

### Tool Instantiation

Override `build_tool` to inject dependencies into tool instances:

```ruby
def build_tool(tool_class)
  tool_class.new(db: DatabasePool.checkout)
end
```

Source: `base_controller.rb:208-210`

### Lifecycle Hooks

```ruby
def before_tool_call(tool_name, arguments)
  Rails.logger.info "MCP tool called: #{tool_name}"
end

def after_tool_call(tool_name, result)
  Metrics.increment("mcp.tool.#{tool_name}")
end
```

Source: `base_controller.rb:213-220`

### Server Metadata

```ruby
def server_info
  { name: "my-app", version: "2.1.0", environment: Rails.env }
end

def server_instructions
  "You are operating on behalf of #{current_user.name}. Always confirm destructive actions."
end
```

Source: `base_controller.rb:223-233`

## Batch Requests

The controller supports JSON-RPC batch requests (arrays of request objects) automatically via `handle_batch_request` (`base_controller.rb:138-143`). Responses are returned as an array in the same order.

## Error Codes

| Code | Constant | Meaning |
|------|---------|---------|
| `-32700` | `PARSE_ERROR` | Invalid JSON |
| `-32600` | `INVALID_REQUEST` | Invalid JSON-RPC |
| `-32601` | `METHOD_NOT_FOUND` | Unknown method |
| `-32602` | `INVALID_PARAMS` | Invalid parameters |
| `-32603` | `INTERNAL_ERROR` | Internal server error |

Source: `base_controller.rb:11-18`

## Tool Schema Conversion

`tool_to_mcp_schema` (`base_controller.rb:426-434`) converts an `ActiveIntelligence::Tool`'s `to_json_schema` output into the MCP `inputSchema` format. Any tool you've already built for use with agents works without modification in an MCP server.
