# lib/active_intelligence.rb
require 'net/http'
require 'json'

module ActiveIntelligence
  class Agent
    # Class methods for DSL
    class << self
      # Define class instance variables with default values
      def inherited(subclass)
        subclass.instance_variable_set(:@model_name, nil)
        subclass.instance_variable_set(:@memory_type, nil)
        subclass.instance_variable_set(:@identity, nil)
      end

      # DSL methods
      def model(model_name)
        @model_name = model_name
      end

      def memory(memory_type)
        @memory_type = memory_type
      end

      def identity(identity_text)
        @identity = identity_text
      end

      # Getters for class instance variables
      def get_model_name
        @model_name
      end

      def get_memory_type
        @memory_type
      end

      def get_identity
        @identity
      end
    end

    # Instance methods
    attr_reader :objective, :messages

    def initialize(objective: nil)
      @objective = objective
      @messages = []
    end

    # Modified to support streaming with an optional block
    def send_message(message, stream: false, &block)
      # Add message to history
      @messages << { role: 'user', content: message }

      # Prepare system prompt
      system_prompt = self.class.get_identity.to_s
      system_prompt += "\n\nYour objective: #{@objective}" if @objective

      # Get response based on model type
      case self.class.get_model_name
       when :claude
         if stream && block_given?
           # Streaming mode with callback
           full_response = call_claude_api_streaming(system_prompt, @messages, &block)
         else
           # Non-streaming mode
           full_response = call_claude_api(system_prompt, @messages)
         end
       else
         full_response = "Error: Unsupported model #{self.class.get_model_name}"
       end

      # Add response to history
      @messages << { role: 'assistant', content: full_response }

      # Return the response
      full_response
    end

    private

    def call_claude_api(system_prompt, messages)
      # Check for API key
      api_key = ENV['ANTHROPIC_API_KEY']
      unless api_key
        return "Error: ANTHROPIC_API_KEY environment variable not set"
      end

      # Convert our internal message format to Claude's format
      formatted_messages = messages.map do |msg|
        { role: msg[:role], content: msg[:content] }
      end

      # API request
      uri = URI('https://api.anthropic.com/v1/messages')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["x-api-key"] = api_key
      request["anthropic-version"] = "2023-06-01"

      request.body = {
        model: "claude-3-opus-20240229",
        system: system_prompt,
        messages: formatted_messages,
        max_tokens: 1024
      }.to_json

      response = http.request(request)

      if response.code == "200"
        result = JSON.parse(response.body)
        return result["content"][0]["text"]
      else
        return "API Error: #{response.code} - #{response.body}"
      end
    rescue => e
      return "Error: #{e.message}"
    end

    def call_claude_api_streaming(system_prompt, messages)
      # Check for API key
      api_key = ENV['ANTHROPIC_API_KEY']
      unless api_key
        error_msg = "Error: ANTHROPIC_API_KEY environment variable not set"
        yield error_msg if block_given?
        return error_msg
      end

      # Convert our internal message format to Claude's format
      formatted_messages = messages.map do |msg|
        { role: msg[:role], content: msg[:content] }
      end

      # API request
      uri = URI('https://api.anthropic.com/v1/messages')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["x-api-key"] = api_key
      request["anthropic-version"] = "2023-06-01"
      # Add this header for streaming
      request["Accept"] = "text/event-stream"

      request.body = {
        model: "claude-3-opus-20240229",
        system: system_prompt,
        messages: formatted_messages,
        max_tokens: 1024,
        stream: true
      }.to_json

      full_response = ""

      begin
        http.request(request) do |response|
          if response.code != "200"
            error_msg = "API Error: #{response.code} - #{response.body}"
            yield error_msg if block_given?
            return error_msg
          end

          buffer = ""

          response.read_body do |chunk|
            buffer += chunk

            # Process complete events from the buffer
            while buffer.include?("\n\n")
              event, buffer = buffer.split("\n\n", 2)
              event_name, event_data = event.split("\n")

              # Skip empty events
              next if event.strip.empty?

              # Process the event
              if event_data.start_with?("data: ")
                data = event_data[6..-1] # Remove "data: " prefix

                # Skip [DONE] message
                next if data.strip == "[DONE]"

                begin
                  json_data = JSON.parse(data)

                  # Extract the text from the event
                  if json_data["type"] == "content_block_delta" && json_data["delta"]["type"] == "text_delta"
                    text = json_data["delta"]["text"]

                    # Append to full response
                    full_response += text

                    # Yield the text chunk to the block
                    yield text if block_given?
                  end
                rescue JSON::ParserError => e
                  # Skip malformed events
                end
              end
            end
          end
        end
      rescue => e
        error_msg = "Error: #{e.message}"
        yield error_msg if block_given?
        return error_msg
      end

      return full_response
    end
  end
end