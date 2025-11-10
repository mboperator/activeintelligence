#!/usr/bin/env ruby

require 'bundler/setup'
require 'activeintelligence'
require_relative '../lib/directory_scanner_tool'
require_relative '../lib/file_reader_tool'
require_relative '../lib/readme_writer_tool'

# README Generator Agent - Analyzes projects and creates comprehensive READMEs
class ReadmeGeneratorAgent < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity <<~IDENTITY
    You are an expert technical writer and software developer who creates comprehensive,
    professional README.md files for software projects.

    Your approach:
    1. First, scan the project directory to understand its structure
    2. Identify key files (package.json, Gemfile, setup.py, etc.) and read them to understand:
       - Project name and description
       - Dependencies and frameworks used
       - Programming language(s)
       - Build tools and scripts
    3. Analyze the codebase structure to understand the architecture
    4. Create a comprehensive README.md that includes:
       - Clear project title and description
       - Installation instructions
       - Usage examples
       - Project structure overview
       - Dependencies and requirements
       - Configuration (if applicable)
       - Contributing guidelines (if appropriate)
       - License information (if found)

    Be thorough but concise. Use clear markdown formatting. Focus on what developers
    need to know to understand and use the project.

    After analyzing the project, present the README content to the user and ask if they
    want you to write it to README.md in the project directory.
  IDENTITY

  tool DirectoryScannerTool
  tool FileReaderTool
  tool ReadmeWriterTool
end

# CLI Interface
def main
  unless ARGV[0]
    puts "\nUsage: ruby bin/readme_generator_agent.rb <project_directory>"
    puts "\nExample:"
    puts "  ruby bin/readme_generator_agent.rb /path/to/my/project"
    puts "  ruby bin/readme_generator_agent.rb ."
    puts "\n"
    exit 1
  end

  project_dir = File.expand_path(ARGV[0])

  unless Dir.exist?(project_dir)
    puts "Error: Directory not found: #{project_dir}"
    exit 1
  end

  puts "\n" + "=" * 80
  puts "README Generator - Powered by ActiveIntelligence"
  puts "=" * 80
  puts "\nAnalyzing project: #{project_dir}"
  puts "This may take a moment as I examine your project...\n\n"

  # Create the agent
  agent = ReadmeGeneratorAgent.new(
    objective: "Analyze the project and create a professional README.md"
  )

  # Initial prompt with streaming
  initial_prompt = <<~PROMPT
    Please analyze the project in this directory and create a comprehensive README.md:

    Directory: #{project_dir}

    Start by scanning the directory structure, then examine key files to understand
    the project. After your analysis, create a professional README.md and present it
    to me for review.
  PROMPT

  begin
    agent.send_message(initial_prompt, stream: true) do |chunk|
      print chunk
      $stdout.flush
    end

    puts "\n\n" + "=" * 80
    puts "Analysis complete!"
    puts "=" * 80
    puts "\n"

  rescue => e
    puts "\n\nError: #{e.message}"
    puts e.backtrace.first(5)
    exit 1
  end
end

main if __FILE__ == $0
