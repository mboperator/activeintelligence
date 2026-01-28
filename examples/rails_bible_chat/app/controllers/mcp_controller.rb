# frozen_string_literal: true

# MCP Server Controller
#
# This controller exposes the Bible Reference Tool via the Model Context Protocol (MCP).
# MCP allows AI applications (like Claude Code) to discover and use tools from this server.
#
# Connect with Claude Code:
#   claude mcp add --transport http bible-mcp http://localhost:3000/mcp
#
# Test with curl (use -c/-b flags to maintain session cookies):
#
#   # 1. Initialize (save cookies)
#   curl -X POST http://localhost:3000/mcp \
#     -H "Content-Type: application/json" -c cookies.txt \
#     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
#
#   # 2. Send initialized notification
#   curl -X POST http://localhost:3000/mcp \
#     -H "Content-Type: application/json" -b cookies.txt -c cookies.txt \
#     -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
#
#   # 3. List tools
#   curl -X POST http://localhost:3000/mcp \
#     -H "Content-Type: application/json" -b cookies.txt \
#     -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
#
#   # 4. Call tool
#   curl -X POST http://localhost:3000/mcp \
#     -H "Content-Type: application/json" -b cookies.txt \
#     -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"bible_lookup","arguments":{"reference":"John 3:16"}}}'
#
class McpController < ActiveIntelligence::MCP::BaseController
  # Register tools to expose via MCP
  # Only backend tools should be exposed (not frontend tools like ShowEmojiTool)
  mcp_tools BibleReferenceTool

  # Server identification
  mcp_server_name 'Bible Study MCP Server'
  mcp_server_version '1.0.0'

  protected

  # Optional: Add authentication
  # def authenticate_mcp_request
  #   # Example: API key authentication
  #   api_key = request.headers['X-API-Key']
  #   api_key == Rails.application.credentials.mcp_api_key
  # end

  # Optional: Customize tool instantiation (dependency injection)
  # def build_tool(tool_class)
  #   tool_class.new(user: current_user)
  # end

  # Optional: Logging/auditing
  def before_tool_call(tool_name, params)
    Rails.logger.info "[MCP] Calling tool: #{tool_name} with params: #{params.inspect}"
  end

  def after_tool_call(tool_name, params, result)
    Rails.logger.info "[MCP] Tool #{tool_name} completed: success=#{result[:success]}"
  end

  # Customize server instructions shown to AI clients
  def server_instructions
    <<~INSTRUCTIONS
      This MCP server provides access to Bible verse lookup functionality.

      Available tools:
      - bible_lookup: Look up Bible verses by reference (e.g., "John 3:16", "Psalm 23")

      Supported Bible translations: KJV, ASV, WEB
    INSTRUCTIONS
  end
end
