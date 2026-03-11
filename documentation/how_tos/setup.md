---
title: Setup
description: Install ActiveIntelligence, configure your API key, and set global options.
tags: [setup, installation, configuration]
---

## Prerequisites

- Ruby 3.0+
- An [Anthropic API key](https://console.anthropic.com) (or OpenAI API key if using OpenAI)
- Bundler

## Installation

Add to your `Gemfile`:

```ruby
gem "activeintelligence"
```

Then:

```bash
bundle install
```

Or install directly:

```bash
gem install activeintelligence
```

## API Key

Set the environment variable before running your application:

```bash
export ANTHROPIC_API_KEY="sk-ant-api03-..."
```

For OpenAI:

```bash
export OPENAI_API_KEY="sk-..."
```

The library reads these variables at runtime. If the key is missing, you'll get a `RuntimeError` on the first API call.

## Basic Usage

```ruby
require "activeintelligence"

class Assistant < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity "You are a helpful assistant."
end

agent = Assistant.new
puts agent.send_message("Hello!")
```

## Global Configuration

Customize defaults with the `configure` block. Place this in an initializer (`config/initializers/active_intelligence.rb` for Rails) or at the top of your script:

```ruby
ActiveIntelligence.configure do |config|
  config.settings[:claude][:model]                  = "claude-3-5-sonnet-latest"
  config.settings[:claude][:max_tokens]             = 8192
  config.settings[:claude][:api_version]            = "2023-06-01"
  config.settings[:claude][:enable_prompt_caching]  = true  # default: true
  config.settings[:logger]                          = Rails.logger
end
```

Source: `config.rb`

### Available Claude Models

| Model ID | Notes |
|----------|-------|
| `claude-3-opus-20240229` | Most capable, slower |
| `claude-3-sonnet-20240229` | Balanced |
| `claude-3-5-sonnet-latest` | Recommended default |
| `claude-3-5-haiku-latest` | Fastest, lowest cost |

### Configuration Options

| Setting | Default | Description |
|---------|---------|-------------|
| `claude.model` | `"claude-3-opus-20240229"` | Default Claude model |
| `claude.max_tokens` | `4096` | Max response length |
| `claude.api_version` | `"2023-06-01"` | Anthropic API version header |
| `claude.enable_prompt_caching` | `true` | Cache system prompt and tools (80-90% cost reduction) |
| `logger` | `Logger.new(STDOUT)` | Logger instance (auto-uses `Rails.logger` in Rails) |

## Per-Agent Model Override

You can override the model per agent class without changing the global default:

```ruby
class HeavyResearchAgent < ActiveIntelligence::Agent
  model :claude
  identity "You are a research assistant."
  # Inherits global model but can be overridden via options:
end

agent = HeavyResearchAgent.new(options: { model: "claude-3-opus-20240229" })
```

## Rails Setup

For Rails, create an initializer and (optionally) run the generator:

```bash
rails generate active_intelligence:install
```

This creates:
- `config/initializers/active_intelligence.rb` — configuration
- A migration for the `conversations` and `messages` tables (if using ActiveRecord memory)

Then run:

```bash
rails db:migrate
```

See [Rails Integration](rails_integration) for full details.
