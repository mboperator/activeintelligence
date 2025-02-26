#!/usr/bin/env ruby

# Include required libraries
require 'logger'
require_relative '../lib/activeintelligence'

# Configure the gem
ActiveIntelligence.configure do |config|
  config.settings[:claude][:model] = "claude-3-sonnet-20240229" # Use a faster model for testing
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
  objective: "Given a specific topic, research the top 7 principles given by God across the Scriptures."
)

# Example 1: Standard request (non-streaming)
# response = agent.send_message("What does the Bible say about being a father?")
# puts "FULL RESPONSE:\n#{response}"

# Example 2: Streaming request
puts "Asking: What does the Bible say about being a father?"
puts "Response:"

agent.send_message("What does the Bible say about being a father?", stream: true) do |chunk|
  print chunk
  $stdout.flush  # Ensure the output is displayed immediately
end

puts "\n\nDone!"
