#!/usr/bin/env ruby

# Include required libraries
require 'logger'
require_relative '../lib/activeintelligence'
require_relative '../lib/dad_joke_tool'

# Configure the gem
ActiveIntelligence.configure do |config|
  config.settings[:claude][:model] = "claude-3-5-sonnet-latest" # Use a faster model for testing
  config.settings[:logger] = Logger.new(STDOUT, level: Logger::INFO)
end

# Define an agent class
class JokeAssistant < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity "You are a friendly assistant who loves dad jokes.
    When given a query, you should use the Dad Joke Tool to find a joke.
    If appropriate, you can add a brief explanation of why the joke is funny,
    but keep your responses conversational and concise."
  
  # Register the DadJokeTool to be used by this agent
  tool ActiveIntelligence::DadJokeTool
end

# Create an agent instance
agent = JokeAssistant.new(
  objective: "Help users lighten their day with some humor, using the Dad Joke Tool to provide jokes."
)

# Print an introduction
puts " Dad Joke Assistant "
puts "----------------------"
puts "Ask me to tell you a joke or just say hi! (Type 'exit' to quit)"
puts

# Interactive loop
loop do
  print "> "
  input = gets.chomp
  
  # Exit condition
  break if input.downcase == 'exit'
  
  # Streaming response
  puts "\nResponse:"
  agent.send_message(input, stream: true) do |chunk|
    print chunk
    $stdout.flush  # Ensure the output is displayed immediately
  end
  
  puts "\n\n"
end

puts "Goodbye! "
