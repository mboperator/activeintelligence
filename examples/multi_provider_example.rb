#!/usr/bin/env ruby
# examples/multi_provider_example.rb
require 'bundler/setup'
require_relative '../lib/activeintelligence'

# Weather tool - works with any provider!
class WeatherTool < ActiveIntelligence::Tool
  name "get_weather"
  description "Get current weather for a location"

  param :location, type: String, required: true, description: "City name"

  def execute(params)
    location = params[:location]

    # Simulate weather API
    weather_data = {
      "San Francisco" => { temp: 65, condition: "Foggy" },
      "New York" => { temp: 72, condition: "Sunny" },
      "London" => { temp: 58, condition: "Rainy" }
    }

    data = weather_data[location] || { temp: 70, condition: "Partly cloudy" }

    success_response({
      location: location,
      temperature: data[:temp],
      condition: data[:condition]
    })
  end
end

# Claude-powered agent
class ClaudeWeatherAgent < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity "You are a friendly weather assistant. Use the weather tool to get current conditions."
  tool WeatherTool
end

# OpenAI-powered agent
class OpenAIWeatherAgent < ActiveIntelligence::Agent
  model :openai
  memory :in_memory
  identity "You are a friendly weather assistant. Use the weather tool to get current conditions."
  tool WeatherTool
end

# Demonstrate both work identically
if __FILE__ == $0
  puts "Multi-Provider Example: Claude vs OpenAI"
  puts "=" * 60
  puts

  question = "What's the weather like in San Francisco?"

  # Test with Claude
  puts "Using CLAUDE:"
  puts "-" * 60
  begin
    claude_agent = ClaudeWeatherAgent.new
    response = claude_agent.send_message(question)
    puts response
  rescue => e
    puts "Error: #{e.message}"
    puts "(Make sure ANTHROPIC_API_KEY is set)"
  end
  puts

  # Test with OpenAI
  puts "Using OPENAI:"
  puts "-" * 60
  begin
    openai_agent = OpenAIWeatherAgent.new
    response = openai_agent.send_message(question)
    puts response
  rescue => e
    puts "Error: #{e.message}"
    puts "(Make sure OPENAI_API_KEY is set)"
  end
  puts

  puts "=" * 60
  puts "Notice: Same tool, same Agent interface, different providers!"
  puts "The abstraction layer handles all provider-specific details."
end
