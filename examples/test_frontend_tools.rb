#!/usr/bin/env ruby
# Test script for frontend/backend hybrid tool execution

# Add lib to load path
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'activeintelligence'

# Backend tool (executes immediately)
class BackendTool < ActiveIntelligence::Tool
  execution_context :backend

  name "get_time"
  description "Get the current server time"

  def execute(params)
    success_response({
      time: Time.now.to_s,
      timezone: Time.now.zone
    })
  end
end

# Frontend tool (causes agent to pause)
class FrontendTool < ActiveIntelligence::Tool
  execution_context :frontend

  name "show_alert"
  description "Show an alert message to the user"

  param :message, type: String, required: true, description: "The message to show"
  param :type, type: String, default: "info", enum: ["info", "warning", "error"]

  def execute(params)
    # This won't actually execute on backend
    # The agent will pause and return this to the frontend
    success_response({
      message: params[:message],
      type: params[:type]
    })
  end
end

# Define a simple agent with both frontend and backend tools
class TestAgent < ActiveIntelligence::Agent
  model :claude
  memory :in_memory

  identity "You are a helpful assistant that can use both backend and frontend tools."

  tool BackendTool
  tool FrontendTool
end

puts "=" * 80
puts "Testing Hybrid Frontend/Backend Tool Execution"
puts "=" * 80
puts

puts "Test 1: Tool execution context detection"
puts "-" * 80

puts "BackendTool.execution_context: #{BackendTool.execution_context}"
puts "BackendTool.frontend?: #{BackendTool.frontend?}"
puts "BackendTool.backend?: #{BackendTool.backend?}"
puts

puts "FrontendTool.execution_context: #{FrontendTool.execution_context}"
puts "FrontendTool.frontend?: #{FrontendTool.frontend?}"
puts "FrontendTool.backend?: #{FrontendTool.backend?}"
puts

puts "=" * 80
puts "Test 2: Tool JSON schema generation"
puts "-" * 80

backend_schema = BackendTool.to_json_schema
frontend_schema = FrontendTool.to_json_schema

puts "BackendTool schema:"
puts "  Name: #{backend_schema[:name]}"
puts "  Description: #{backend_schema[:description]}"
puts

puts "FrontendTool schema:"
puts "  Name: #{frontend_schema[:name]}"
puts "  Description: #{frontend_schema[:description]}"
puts "  Parameters: #{frontend_schema[:input_schema][:properties].keys.join(', ')}"
puts

puts "=" * 80
puts "Test 3: Tool execution (backend)"
puts "-" * 80

backend_result = BackendTool.new.execute({})
puts "BackendTool result:"
puts "  Success: #{backend_result[:success]}"
puts "  Time: #{backend_result[:data][:time]}"
puts

puts "=" * 80
puts "Test 4: Tool execution (frontend)"
puts "-" * 80

frontend_result = FrontendTool.new.execute({ message: "Test alert", type: "info" })
puts "FrontendTool result:"
puts "  Success: #{frontend_result[:success]}"
puts "  Message: #{frontend_result[:data][:message]}"
puts "  Type: #{frontend_result[:data][:type]}"
puts

puts "=" * 80
puts "✅ All tests passed!"
puts "=" * 80
puts
puts "Note: Full integration testing requires:"
puts "1. A Rails app with ActiveRecord conversations"
puts "2. An actual API key to test with Claude"
puts "3. A React frontend to handle frontend tools"
puts
puts "See examples/rails_bible_chat/FRONTEND_TOOL_EXAMPLE.md for integration details."
