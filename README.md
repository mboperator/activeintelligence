# ActiveIntelligence

A gem for building AI agents.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'activeintelligence'
```

And then execute:

```
$ bundle install
```

Or install it yourself as:

```
$ gem install activeintelligence
```

## Configuration

You can configure the gem globally:

```ruby
ActiveIntelligence.configure do |config|
  config.settings[:claude][:model] = "claude-3-opus-20240229"
  config.settings[:claude][:max_tokens] = 2000
  config.settings[:logger] = Logger.new("log/activeintelligence.log")
end
```

## Usage

### Creating an Agent

```ruby
class SeminaryProfessor < ActiveIntelligence::Agent
  model :claude
  memory :in_memory
  identity "You are a professor at a leading seminary teaching reform Christian theology.
You enjoy helping other believers understand the Bible more deeply.
All of your answers are rooted in Biblical Truth."
end
```

### Initializing an Agent

```ruby
agent = SeminaryProfessor.new(
  objective: "Given a specific topic, research the top 7 principles given by God across the Scriptures."
)
```

### Sending Messages

Standard (non-streaming) request:

```ruby
response = agent.send_message("What does the Bible say about being a father?")
puts response
```

Streaming request:

```ruby
agent.send_message("What does the Bible say about being a father?", stream: true) do |chunk|
  print chunk
  $stdout.flush  # Ensure the output is displayed immediately
end
```

## Environment Variables

- `ANTHROPIC_API_KEY`: Your Anthropic API key for Claude models

## Features

- Simple DSL for creating LLM-backed agents
- Streaming responses support
- Configurable model parameters
- In-memory conversation history
- Clean error handling

## Project Structure

```
lib/
├── activeintelligence.rb
├── activeintelligence/
    ├── agent.rb
    ├── config.rb
    ├── api_clients/
        ├── base_client.rb
        ├── claude_client.rb
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create new Pull Request
