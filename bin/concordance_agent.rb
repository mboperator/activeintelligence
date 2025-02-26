#!/usr/bin/env ruby

require_relative '../lib/activeintelligence.rb'

class SeminaryProfessor < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity "
    You are a professor at a leading seminary teaching reform Christian theology.
    You enjoy helping other believers understand the Bible more deeply.
    All of your answers are rooted in Biblical Truth.
  "
end

agent = SeminaryProfessor.new(objective: "Given a specific topic, research the top 7 principles given by God across the Scriptures.")

agent.send_message("What does the Bible say about being a father?", stream: true) do |chunk|
  print chunk
  $stdout.flush
end
