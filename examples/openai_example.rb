#!/usr/bin/env ruby
# examples/openai_example.rb
require 'bundler/setup'
require_relative '../lib/activeintelligence'

# Simple calculator tool
class CalculatorTool < ActiveIntelligence::Tool
  name "calculate"
  description "Perform basic arithmetic calculations"

  param :expression, type: String, required: true, description: "Mathematical expression to evaluate (e.g., '2 + 2', '10 * 5')"

  def execute(params)
    expression = params[:expression]

    # Simple safe evaluation for basic arithmetic
    result = eval(expression) rescue nil

    if result
      success_response({ result: result, expression: expression })
    else
      error_response("Invalid expression", details: "Could not evaluate: #{expression}")
    end
  end

  rescue_from StandardError do |e|
    error_response("Calculation failed", details: e.message)
  end
end

# Agent using OpenAI
class OpenAICalculatorAgent < ActiveIntelligence::Agent
  model :openai  # ← Using OpenAI!
  memory :in_memory

  identity "You are a helpful math assistant. When asked to calculate something, use the calculate tool."

  tool CalculatorTool
end

# Example usage
if __FILE__ == $0
  puts "OpenAI Calculator Agent Example"
  puts "=" * 50
  puts

  agent = OpenAICalculatorAgent.new

  # Test 1: Simple calculation
  puts "User: What is 25 * 4?"
  response = agent.send_message("What is 25 * 4?")
  puts "Agent: #{response}"
  puts

  # Test 2: Another calculation
  puts "User: Calculate 100 / 5"
  response = agent.send_message("Calculate 100 / 5")
  puts "Agent: #{response}"
  puts

  # Test 3: No tool needed
  puts "User: Hello, how are you?"
  response = agent.send_message("Hello, how are you?")
  puts "Agent: #{response}"
end
