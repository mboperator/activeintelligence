# lib/active_intelligence/api_clients/claude_client.rb
module ActiveIntelligence
  module ApiClients
    class ClaudeClient < BaseClient
      ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages".freeze

      def initialize(options = {})
        super
        @api_key = options[:api_key] || ENV['ANTHROPIC_API_KEY']
        @model = options[:model] || Config.settings[:claude][:model]
        @api_version = options[:api_version] || Config.settings[:claude][:api_version]
        @max_tokens = options[:max_tokens] || Config.settings[:claude][:max_tokens]

        raise ConfigurationError, "Anthropic API key is required" unless @api_key
      end

      def call(messages, system_prompt, options = {})
        params = build_request_params(messages, system_prompt, options)

        uri = URI(ANTHROPIC_API_URL)
        http = setup_http_client(uri)
        request = build_request(uri, params)

        response = http.request(request)
        process_response(response)
      rescue => e
        handle_error(e)
      end

      def call_streaming(messages, system_prompt, options = {}, &block)
        params = build_request_params(messages, system_prompt, options.merge(stream: true))

        uri = URI(ANTHROPIC_API_URL)
        http = setup_http_client(uri)
        request = build_request(uri, params, stream: true)

        http.request(request) do |response|
          if response.code != "200"
            error_msg = handle_error(StandardError.new("#{response.code} - #{response.body}"))
            yield error_msg if block_given?
            return error_msg
          end

          result = process_streaming_response(response, &block)
          return result
        end
      rescue => e
        error_msg = handle_error(e)
        yield error_msg if block_given?
        error_msg
      end

      private

      def build_request_params(messages, system_prompt, options)
        params = {
          model: options[:model] || @model,
          system: system_prompt,
          messages: messages,
          max_tokens: options[:max_tokens] || @max_tokens,
          stream: options[:stream] || false
        }

        # Add tools if provided
        if options[:tools] && !options[:tools].empty?
          params[:tools] = options[:tools]
        end

        params
      end

      def setup_http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 300 # 5 minutes timeout for streaming
        http
      end

      def build_request(uri, params, stream: false)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["x-api-key"] = @api_key
        request["anthropic-version"] = @api_version

        if stream
          request["Accept"] = "text/event-stream"
        end

        request.body = params.to_json
        request
      end

      def process_response(response)
        case response.code
        when "200"
          result = safe_parse_json(response.body)

          if result && result["content"]
            # Check if there are tool calls in the response
            tool_calls = result["content"].select { |message| message["type"] == "tool_use" }
            content = result["content"].select { |message| message["type"] == "text" }

            if tool_calls && !tool_calls.empty?
              return {
                content: content[0]["text"],
                tool_calls: tool_calls.map do |tc|
                  {
                    name: tc["name"],
                    parameters: tc["input"]
                  }
                end
              }
            end

            # Standard text response
            return {
              content: content[0]["text"],
              tool_calls: []
            }
          end

          "Error: Unable to parse response"
        else
          "API Error: #{response.code} - #{response.body}"
        end
      end

      def process_streaming_response(response, &block)
        full_response = ""
        tool_call_detected = false
        tool_call_name = nil
        tool_call_params = {}

        buffer = ""

        response.read_body do |chunk|
          buffer += chunk

          # Process complete SSE events from the buffer
          while buffer.include?("\n\n")
            event, buffer = buffer.split("\n\n", 2)

            # Skip empty events
            next if event.strip.empty?

            # Find the data line
            data_line = event.split("\n").find { |line| line.start_with?("data: ") }
            next unless data_line

            data = data_line[6..-1] # Remove "data: " prefix

            # Skip [DONE] message
            next if data.strip == "[DONE]"

            json_data = safe_parse_json(data)
            next unless json_data

            # Extract the text from the event
            if json_data["type"] == "content_block_delta" && json_data["delta"]["type"] == "text_delta"
              text = json_data["delta"]["text"]

              # Append to full response
              full_response << text

              # Yield the text chunk to the block
              yield text if block_given?
            end
            if json_data["type"] == "content_block_start" && json_data["content_block"]["type"] == "tool_use"
              tool_call_detected = true
              tool_call = json_data["content_block"]
              tool_call_name = tool_call["name"]
              tool_call_params = tool_call["input"]
            end
          end
        end

        if tool_call_detected
          {
            content: full_response,
            tool_calls: [
              {
                name: tool_call_name,
                parameters: tool_call_params
              }
            ]
          }
        else
          {
            content: full_response,
            tool_calls: []
          }
        end
      end
    end
  end
end