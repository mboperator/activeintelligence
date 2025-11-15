# lib/activeintelligence/api_clients/openai_client.rb
module ActiveIntelligence
  module ApiClients
    class OpenAIClient < BaseClient
      OPENAI_API_URL = "https://api.openai.com/v1/chat/completions".freeze

      def initialize(options = {})
        super
        @api_key = options[:api_key] || ENV['OPENAI_API_KEY']
        @model = options[:model] || 'gpt-4o'
        @max_tokens = options[:max_tokens] || 4096

        raise ConfigurationError, "OpenAI API key is required" unless @api_key
      end

      def call(messages, system_prompt, options = {})
        Instrumentation.instrument('api_call', provider: :openai, model: @model, message_count: messages.length) do |payload|
          start_time = Time.now

          formatted_messages = format_messages(messages, system_prompt)
          params = build_request_params(formatted_messages, options)

          # Log API request if enabled
          if Config.settings[:log_api_requests]
            Config.log(:debug, {
              event: 'api_request',
              provider: 'openai',
              url: OPENAI_API_URL,
              model: @model,
              message_count: messages.length,
              system_prompt_length: system_prompt&.length || 0,
              tools_count: options[:tools]&.length || 0
            })
          end

          uri = URI(OPENAI_API_URL)
          http = setup_http_client(uri)
          request = build_request(uri, params)

          response = http.request(request)
          result = normalize_response(response)

          # Calculate metrics
          duration_ms = ((Time.now - start_time) * 1000).round(2)

          # Log API response
          if Config.settings[:log_token_usage] && result[:usage]
            Config.log(:info, {
              event: 'api_response',
              provider: 'openai',
              model: @model,
              duration_ms: duration_ms,
              usage: result[:usage],
              stop_reason: result[:stop_reason],
              tool_calls_count: result[:tool_calls]&.length || 0
            })
          end

          # Enrich instrumentation payload
          payload[:duration_ms] = duration_ms
          payload[:usage] = result[:usage]
          payload[:stop_reason] = result[:stop_reason]
          payload[:tool_calls_count] = result[:tool_calls]&.length || 0

          result
        end
      rescue => e
        Config.log(:error, {
          event: 'api_error',
          provider: 'openai',
          error: e.class.name,
          error_message: e.message
        })
        handle_error(e)
      end

      def call_streaming(messages, system_prompt, options = {}, &block)
        Instrumentation.instrument('api_call_streaming', provider: :openai, model: @model, message_count: messages.length) do |payload|
          start_time = Time.now

          formatted_messages = format_messages(messages, system_prompt)
          params = build_request_params(formatted_messages, options.merge(stream: true))

          # Log API request if enabled
          if Config.settings[:log_api_requests]
            Config.log(:debug, {
              event: 'api_request_streaming',
              provider: 'openai',
              url: OPENAI_API_URL,
              model: @model,
              message_count: messages.length,
              system_prompt_length: system_prompt&.length || 0,
              tools_count: options[:tools]&.length || 0
            })
          end

          uri = URI(OPENAI_API_URL)
          http = setup_http_client(uri)
          request = build_request(uri, params)

          result = nil
          http.request(request) do |response|
            if response.code != "200"
              error_msg = handle_error(StandardError.new("#{response.code} - #{response.body}"))
              yield error_msg if block_given?
              return error_msg
            end

            result = process_streaming_response(response, &block)
          end

          # Calculate metrics
          duration_ms = ((Time.now - start_time) * 1000).round(2)

          # Log API response
          if Config.settings[:log_token_usage] && result[:usage]
            Config.log(:info, {
              event: 'api_response_streaming',
              provider: 'openai',
              model: @model,
              duration_ms: duration_ms,
              usage: result[:usage],
              stop_reason: result[:stop_reason],
              tool_calls_count: result[:tool_calls]&.length || 0
            })
          end

          # Enrich instrumentation payload
          payload[:duration_ms] = duration_ms
          payload[:usage] = result[:usage]
          payload[:stop_reason] = result[:stop_reason]
          payload[:tool_calls_count] = result[:tool_calls]&.length || 0

          result
        end
      rescue => e
        Config.log(:error, {
          event: 'api_error_streaming',
          provider: 'openai',
          error: e.class.name,
          error_message: e.message
        })
        error_msg = handle_error(e)
        yield error_msg if block_given?
        error_msg
      end

      private

      # Format Message objects into OpenAI API format
      def format_messages(messages, system_prompt)
        formatted = []

        # OpenAI puts system prompt as first message
        formatted << { role: "system", content: system_prompt } if system_prompt&.strip&.length&.positive?

        messages.each do |msg|
          formatted << format_single_message(msg)
        end

        formatted
      end

      def format_single_message(msg)
        case msg
        when Messages::ToolResponse
          # OpenAI uses role "tool"
          {
            role: "tool",
            tool_call_id: msg.tool_use_id,
            content: msg.content
          }
        when Messages::AgentResponse
          if msg.tool_calls.empty?
            # Simple text response
            { role: "assistant", content: msg.content }
          else
            # Response with tool calls
            message = {
              role: "assistant",
              content: msg.content
            }

            message[:tool_calls] = msg.tool_calls.map do |tc|
              {
                id: tc[:id],
                type: "function",
                function: {
                  name: tc[:name],
                  arguments: tc[:parameters].to_json  # OpenAI wants JSON string
                }
              }
            end

            message
          end
        else
          # Simple message (UserMessage, etc.)
          { role: msg.role, content: msg.content }
        end
      end

      def build_request_params(messages, options)
        params = {
          model: options[:model] || @model,
          messages: messages,
          max_tokens: options[:max_tokens] || @max_tokens
        }

        # Add stream parameter if streaming
        params[:stream] = true if options[:stream]

        # Add tools if provided
        if options[:tools] && !options[:tools].empty?
          # Convert ActiveIntelligence tool format to OpenAI format
          params[:tools] = options[:tools].map do |tool|
            {
              type: "function",
              function: {
                name: tool[:name],
                description: tool[:description],
                parameters: tool[:input_schema]
              }
            }
          end
        end

        params
      end

      def setup_http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 300 # 5 minutes timeout for streaming
        http
      end

      def build_request(uri, params)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@api_key}"

        request.body = params.to_json
        request
      end

      # Normalize OpenAI response to common format
      def normalize_response(response)
        case response.code
        when "200"
          result = safe_parse_json(response.body)

          if result && result["choices"] && result["choices"].length > 0
            choice = result["choices"][0]
            message = choice["message"]

            tool_calls = []
            if message["tool_calls"]
              tool_calls = message["tool_calls"].map do |tc|
                {
                  id: tc["id"],
                  name: tc["function"]["name"],
                  parameters: safe_parse_json(tc["function"]["arguments"]) || {}
                }
              end
            end

            # Check finish_reason for issues
            finish_reason = choice["finish_reason"]
            if finish_reason == "length"
              logger.warn "Response was truncated due to max_tokens limit. Consider increasing max_tokens."
            end

            # Extract usage information
            usage = result["usage"] ? {
              input_tokens: result["usage"]["prompt_tokens"],
              output_tokens: result["usage"]["completion_tokens"],
              total_tokens: result["usage"]["total_tokens"]
            } : nil

            return {
              content: message["content"] || "",
              tool_calls: tool_calls,
              stop_reason: finish_reason,
              usage: usage
            }
          end

          "Error: Unable to parse response"
        else
          "API Error: #{response.code} - #{response.body}"
        end
      end

      def process_streaming_response(response, &block)
        full_response = ""
        tool_calls = {}
        finish_reason = nil
        usage = nil
        buffer = ""

        response.read_body do |chunk|
          buffer += chunk

          # Process complete SSE events from buffer
          while buffer.include?("\n\n")
            event, buffer = buffer.split("\n\n", 2)

            # Skip empty events
            next if event.strip.empty?

            # Find data line
            data_line = event.split("\n").find { |line| line.start_with?("data: ") }
            next unless data_line

            data = data_line[6..-1] # Remove "data: " prefix

            # Skip [DONE] message
            next if data.strip == "[DONE]"

            json_data = safe_parse_json(data)
            next unless json_data

            # Extract usage (OpenAI sends this in the final chunk)
            if json_data["usage"]
              usage = {
                input_tokens: json_data["usage"]["prompt_tokens"],
                output_tokens: json_data["usage"]["completion_tokens"],
                total_tokens: json_data["usage"]["total_tokens"]
              }
            end

            # Extract delta
            if json_data["choices"] && json_data["choices"].length > 0
              delta = json_data["choices"][0]["delta"]

              # Handle text content
              if delta["content"]
                text = delta["content"]
                full_response << text
                yield text if block_given?
              end

              # Handle tool calls
              if delta["tool_calls"]
                delta["tool_calls"].each do |tc|
                  index = tc["index"]
                  tool_calls[index] ||= { id: nil, name: nil, arguments: "" }

                  tool_calls[index][:id] = tc["id"] if tc["id"]
                  tool_calls[index][:name] = tc["function"]["name"] if tc["function"] && tc["function"]["name"]
                  tool_calls[index][:arguments] << tc["function"]["arguments"] if tc["function"] && tc["function"]["arguments"]
                end
              end

              # Capture finish reason
              finish_reason = json_data["choices"][0]["finish_reason"] if json_data["choices"][0]["finish_reason"]
            end
          end
        end

        # Parse accumulated tool call arguments
        parsed_tool_calls = tool_calls.values.map do |tc|
          {
            id: tc[:id],
            name: tc[:name],
            parameters: safe_parse_json(tc[:arguments]) || {}
          }
        end

        # Check finish_reason for issues
        if finish_reason == "length"
          logger.warn "Response was truncated due to max_tokens limit. Consider increasing max_tokens."
        end

        {
          content: full_response,
          tool_calls: parsed_tool_calls,
          stop_reason: finish_reason,
          usage: usage
        }
      end
    end
  end
end
