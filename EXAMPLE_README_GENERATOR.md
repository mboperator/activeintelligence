# README Generator Agent - Usage Guide

This example demonstrates the **README Generator Agent** - a streaming AI agent that analyzes project directories and creates comprehensive README.md files.

## Features Demonstrated

This agent showcases:
- ✅ **Multiple tools per turn** - Scans directories, reads files, and writes output
- ✅ **Streaming responses** - Real-time output as the agent works
- ✅ **Loop until completion** - Automatically continues analysis until done
- ✅ **Intelligent tool orchestration** - Agent decides which files to examine
- ✅ **Production-ready error handling** - Graceful handling of missing files, permissions, etc.

## Tools Used

### 1. DirectoryScannerTool
Scans project directories and lists all files, excluding common patterns like:
- `.git`, `node_modules`, `vendor`
- Build outputs (`dist`, `build`, `target`)
- Cache directories

### 2. FileReaderTool
Reads file contents with safety limits:
- Max 500 lines per file (configurable)
- Max 1MB file size
- Handles permissions and missing files gracefully

### 3. ReadmeWriterTool
Writes README.md with backup support:
- Creates timestamped backups of existing READMEs
- Validates directory permissions
- Returns detailed success/failure information

## Usage

```bash
# Set your API key
export ANTHROPIC_API_KEY="your-key-here"

# Run on current directory
ruby bin/readme_generator_agent.rb .

# Run on specific project
ruby bin/readme_generator_agent.rb /path/to/project

# Example: Analyze this gem itself
ruby bin/readme_generator_agent.rb /home/user/activeintelligence
```

## Example Output

```
================================================================================
README Generator - Powered by ActiveIntelligence
================================================================================

Analyzing project: /path/to/project
This may take a moment as I examine your project...

Let me analyze this project for you. I'll start by scanning the directory structure...

[Tool: scan_directory]
Found 47 files across 12 directories...

[Tool: read_file - package.json]
[Tool: read_file - src/index.js]
[Tool: read_file - .gitignore]

Based on my analysis, this appears to be a Node.js project...

Here's the README.md I've created:

# Project Name

[Generated README content here]

Would you like me to write this to README.md?

================================================================================
Analysis complete!
================================================================================
```

## How It Works

The agent follows this workflow:

1. **Scan Directory** - Uses `scan_directory` to map the project structure
2. **Identify Key Files** - Looks for package.json, Gemfile, setup.py, etc.
3. **Read Configuration** - Uses `read_file` on multiple files in parallel
4. **Analyze Structure** - Understands dependencies, language, framework
5. **Generate README** - Creates comprehensive documentation
6. **Write Output** - Optionally saves to README.md with backup

## Multi-Tool Performance

This agent benefits from all the optimizations in this PR:

### Before (original gem):
```
Turn 1: Scan directory → 1 API call
Turn 2: Read package.json → 1 API call
Turn 3: Read index.js → 1 API call
Turn 4: Read config → 1 API call
Turn 5: Generate README → 1 API call
Turn 6: Write file → 1 API call

Total: 6+ API calls, sequential execution
```

### After (optimized):
```
Turn 1: Scan directory → 1 API call
Turn 2: [Read package.json, Read index.js, Read config] → 1 API call (all in parallel!)
Turn 3: Generate & write README → 1 API call

Total: 3 API calls, parallel tool execution
Cost: 80% less with prompt caching
```

## Customization

You can customize the agent by modifying:

### Agent Identity
Edit the system prompt in `bin/readme_generator_agent.rb` to change:
- README style and tone
- Sections to include
- Analysis depth

### Tool Parameters
Adjust tool behavior:
```ruby
# Scan deeper directories
param :max_depth, default: 5  # Instead of 3

# Read more lines
param :max_lines, default: 1000  # Instead of 500
```

### Add More Tools
Extend functionality with additional tools:
- `GitLogTool` - Analyze commit history
- `DependencyAnalyzerTool` - Check for outdated packages
- `LicenseDetectorTool` - Identify project license
- `TestCoverageTool` - Include test information

## Code Example

Here's how simple it is to use:

```ruby
require 'activeintelligence'
require_relative '../lib/directory_scanner_tool'
require_relative '../lib/file_reader_tool'
require_relative '../lib/readme_writer_tool'

class ReadmeGeneratorAgent < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity "You are an expert technical writer..."

  tool DirectoryScannerTool
  tool FileReaderTool
  tool ReadmeWriterTool
end

agent = ReadmeGeneratorAgent.new
agent.send_message("Analyze /my/project", stream: true) do |chunk|
  print chunk  # Real-time streaming output!
end
```

## Why This Works So Well

The combination of:
1. **Intelligent tool selection** - Agent picks the right tools at the right time
2. **Parallel execution** - Multiple file reads in one turn
3. **Streaming output** - See progress in real-time
4. **Loop until complete** - No manual intervention needed
5. **Prompt caching** - 80-90% cost reduction on repeated runs

Makes this agent fast, efficient, and cost-effective!

## Try It Yourself

```bash
# Clone and setup
cd activeintelligence
bundle install

# Set API key
export ANTHROPIC_API_KEY="your-key"

# Generate README for any project
ruby bin/readme_generator_agent.rb ../your-project
```

---

**Built with ActiveIntelligence** - Production-ready AI agents with Claude Code-level performance.
