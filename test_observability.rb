#!/usr/bin/env ruby
require_relative 'lib/activeintelligence'
require 'logger'

# Configure with observability enabled
ActiveIntelligence.configure do |config|
  config.settings[:claude][:model] = "claude-3-5-haiku-latest"
  config.settings[:claude][:max_tokens] = 1024
  config.settings[:logger] = Logger.new(STDOUT, level: Logger::INFO)

  # Enable observability features
  config.settings[:log_level] = :info
  config.settings[:log_api_requests] = false
  config.settings[:log_tool_executions] = true
  config.settings[:log_token_usage] = true
  config.settings[:structured_logging] = false  # Use plain text for readability in test
  config.settings[:enable_notifications] = false  # ActiveSupport not loaded in standalone
end

# Simple test agent with callbacks
class TestAgent < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity "You are a helpful test assistant. Be concise."

  before_message do |data|
    puts "\n[CALLBACK] Before message: #{data[:content][0..50]}..."
  end

  after_message do |data|
    puts "[CALLBACK] After message - Response length: #{data[:response].content.length} chars"
    puts "[CALLBACK] Metrics: #{data[:metrics][:messages]}"
  end

  on_error do |data|
    puts "[CALLBACK] Error occurred: #{data[:error].class.name}"
  end
end

puts "=" * 80
puts "ActiveIntelligence Observability Test"
puts "=" * 80

begin
  # Create agent
  puts "\n1. Creating agent..."
  agent = TestAgent.new(objective: "Test observability features")
  puts "✓ Agent created successfully"

  # Send a simple message
  puts "\n2. Sending message (non-streaming)..."
  response = agent.send_message("Say hello in one sentence.")
  puts "Response: #{response}"

  # Check metrics
  puts "\n3. Checking metrics..."
  metrics = agent.metrics.to_h
  puts "✓ Messages: #{metrics[:messages][:total]} total (#{metrics[:messages][:user]} user, #{metrics[:messages][:agent]} agent)"
  puts "✓ Tokens: #{metrics[:tokens][:total]} total (#{metrics[:tokens][:input]} input, #{metrics[:tokens][:output]} output)"
  puts "✓ API calls: #{metrics[:api_calls][:total]} (avg latency: #{metrics[:api_calls][:average_latency_ms].round(2)}ms)"
  puts "✓ Estimated cost: $#{metrics[:estimated_cost_usd]}"
  puts "✓ Uptime: #{metrics[:uptime_seconds]}s"

  # Pretty print
  puts "\n4. Pretty-printed metrics:"
  puts agent.metrics.to_s

  puts "\n5. Testing second message for metric accumulation..."
  response2 = agent.send_message("What's 2+2? One sentence only.")
  puts "Response: #{response2}"

  # Check updated metrics
  puts "\n6. Updated metrics after second message:"
  updated_metrics = agent.metrics.to_h
  puts "✓ Total messages: #{updated_metrics[:messages][:total]}"
  puts "✓ Total tokens: #{updated_metrics[:tokens][:total]}"
  puts "✓ Total API calls: #{updated_metrics[:api_calls][:total]}"
  puts "✓ Total cost: $#{updated_metrics[:estimated_cost_usd]}"

  puts "\n" + "=" * 80
  puts "✓ All observability tests passed!"
  puts "=" * 80

rescue => e
  puts "\n❌ Test failed: #{e.class.name}: #{e.message}"
  puts e.backtrace.first(10).join("\n")
  exit 1
end
