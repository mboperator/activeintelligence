#!/usr/bin/env ruby

# Include required libraries
require 'logger'
require_relative '../lib/activeintelligence'

# Configure the gem
ActiveIntelligence.configure do |config|
  config.settings[:claude][:model] = "claude-3-5-haiku-latest" # Use a faster model for testing
  config.settings[:logger] = Logger.new(STDOUT, level: Logger::INFO)
end

# Define an agent class
class SeminaryProfessor < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity "You are a professor at a leading seminary teaching reform Christian theology.
    You enjoy helping other believers understand the Bible more deeply.
    All of your answers are rooted in Biblical Truth."
end

# Create an agent instance
agent = SeminaryProfessor.new(
  objective: "Your objective is to chat with the user in a way that glorifies Christ"
)

loop do
  print "> "
  input = gets.chomp

  # Exit condition
  break if input.downcase == 'exit'

  # Streaming response
  puts "\nResponse:"
  response = agent.send_message(input)
  puts response
  puts "\n\n"
end

puts "\n\nDone!"
