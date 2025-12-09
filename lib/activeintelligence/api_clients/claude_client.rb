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
        formatted_messages = format_messages(messages)
        params = build_request_params(formatted_messages, system_prompt, options)

        with_retry(options) do
          uri = URI(ANTHROPIC_API_URL)
          http = setup_http_client(uri)
          request = build_request(uri, params)

          response = http.request(request)
          handle_response_status(response)
          process_response(response)
        end
      rescue ApiRateLimitError
        # Re-raise rate limit errors so caller can handle them
        raise
      rescue => e
        handle_error(e)
      end

      def call_streaming(messages, system_prompt, options = {}, &block)
        formatted_messages = format_messages(messages)
        params = build_request_params(formatted_messages, system_prompt, options.merge(stream: true))

        with_retry(options) do
          uri = URI(ANTHROPIC_API_URL)
          http = setup_http_client(uri)
          request = build_request(uri, params, stream: true)

          result = nil
          http.request(request) do |response|
            handle_response_status(response)
            result = process_streaming_response(response, &block)
          end
          result
        end
      rescue ApiRateLimitError
        # Re-raise rate limit errors so caller can handle them
        raise
      rescue => e
        error_msg = handle_error(e)
        yield error_msg if block_given?
        error_msg
      end

      private

      # Format Message objects into Claude API format
      def format_messages(messages)
        # Filter out pending tool responses - Claude shouldn't see them yet
        messages
          .reject { |msg| msg.is_a?(Messages::ToolResponse) && msg.pending? }
          .chunk_while { |msg1, msg2|
            # Group consecutive ToolResponses together
            msg1.is_a?(Messages::ToolResponse) && msg2.is_a?(Messages::ToolResponse)
          }
          .flat_map { |chunk| format_message_chunk(chunk) }
      end

      def format_message_chunk(chunk)
        first = chunk.first

        case first
        when Messages::ToolResponse
          # Group consecutive tool responses into single message
          [{
            role: "user",
            content: chunk.map { |tr|
              {
                type: "tool_result",
                tool_use_id: tr.tool_use_id,
                content: tr.content,
                is_error: tr.is_error
              }
            }
          }]
        when Messages::AgentResponse
          if first.tool_calls.empty?
            # Simple text response
            [{ role: first.role, content: first.content }]
          else
            # Response with tool calls - use content blocks
            content_blocks = []
            content_blocks << { type: "text", text: first.content } unless first.content.to_s.empty?

            first.tool_calls.each do |tc|
              content_blocks << {
                type: "tool_use",
                id: tc[:id],
                name: tc[:name],
                input: tc[:parameters]
              }
            end

            [{ role: first.role, content: content_blocks }]
          end
        else
          # Simple message (UserMessage, etc.)
          [{ role: first.role, content: first.content }]
        end
      end

      def build_request_params(messages, system_prompt, options)
        params = {
          model: options[:model] || @model,
          messages: messages,
          max_tokens: options[:max_tokens] || @max_tokens,
          stream: options[:stream] || false
        }

        # Add system prompt with caching if enabled
        if options[:enable_prompt_caching] != false  # Default to true
          params[:system] = [
            {
              type: "text",
              text: system_prompt,
              cache_control: { type: "ephemeral" }
            }
          ]
        else
          params[:system] = system_prompt
        end

        # Add tools if provided, with caching on last tool
        if options[:tools] && !options[:tools].empty?
          tools = options[:tools].dup
          # Mark the last tool for caching (most benefit)
          if options[:enable_prompt_caching] != false && tools.size > 0
            tools[-1] = tools[-1].merge(cache_control: { type: "ephemeral" })
          end
          params[:tools] = tools
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
            # Check stop_reason for issues
            stop_reason = result["stop_reason"]
            if stop_reason == "max_tokens"
              Config.logger.warn "Response was truncated due to max_tokens limit. Consider increasing max_tokens."
            end

            # Extract usage data
            usage = extract_usage(result["usage"])

            # Check if there are tool calls in the response
            tool_calls = result["content"].select { |message| message["type"] == "tool_use" }
            content = result["content"].select { |message| message["type"] == "text" }
            thinking_blocks = result["content"].select { |message| message["type"] == "thinking" }

            # Extract thinking content
            thinking_content = thinking_blocks.map { |tb| tb["thinking"] }.join("\n")

            # Log thinking blocks for debugging (optional)
            if !thinking_blocks.empty? && Config.logger
              thinking_blocks.each do |tb|
                Config.logger.debug "Claude thinking: #{tb['thinking']}"
              end
            end

            # Safely extract text content (may be empty if only tool calls)
            text_content = content.first&.dig("text") || ""

            if tool_calls && !tool_calls.empty?
              return {
                content: text_content,
                tool_calls: tool_calls.map do |tc|
                  {
                    id: tc["id"],
                    name: tc["name"],
                    parameters: tc["input"]
                  }
                end,
                stop_reason: stop_reason,
                usage: usage,
                thinking: thinking_content.empty? ? nil : thinking_content,
                model: result["model"]
              }
            end

            # Standard text response
            return {
              content: text_content,
              tool_calls: [],
              stop_reason: stop_reason,
              usage: usage,
              thinking: thinking_content.empty? ? nil : thinking_content,
              model: result["model"]
            }
          end

          "Error: Unable to parse response"
        else
          "API Error: #{response.code} - #{response.body}"
        end
      end

      def process_streaming_response(response, &block)
        full_response = ""
        tool_calls = []
        stop_reason = nil
        thinking_content = ""
        current_tool_input = {}  # Track tool inputs by index
        usage_data = nil
        model = nil
        chunk_index = 0
        thinking_started = false

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

            # Capture model from message_start
            if json_data["type"] == "message_start" && json_data["message"]
              model = json_data["message"]["model"]
              # Initial usage from message_start
              if json_data["message"]["usage"]
                usage_data = extract_usage(json_data["message"]["usage"])
              end
            end

            # Extract the text from the event
            if json_data["type"] == "content_block_delta" && json_data["delta"]["type"] == "text_delta"
              text = json_data["delta"]["text"]

              # Append to full response
              full_response << text

              # Yield JSON-wrapped SSE event to the block
              event_data = { type: "content_delta", delta: text, chunk_index: chunk_index }.to_json
              chunk_index += 1
              yield "data: #{event_data}\n\n" if block_given?
            end

            # Detect thinking block start
            if json_data["type"] == "content_block_start" && json_data["content_block"]["type"] == "thinking"
              thinking_started = true
              # Yield thinking_start event
              event_data = { type: "thinking_start" }.to_json
              yield "data: #{event_data}\n\n" if block_given?
            end

            # Capture thinking blocks
            if json_data["type"] == "content_block_delta" && json_data["delta"]["type"] == "thinking_delta"
              thinking_content << json_data["delta"]["thinking"] if json_data["delta"]["thinking"]
            end

            # Detect thinking block end
            if json_data["type"] == "content_block_stop" && thinking_started
              # Check if this was a thinking block (we track via thinking_started flag)
              # This is a simplification - in practice you'd track block types by index
              if !thinking_content.empty?
                thinking_started = false
                event_data = { type: "thinking_end", content: thinking_content }.to_json
                yield "data: #{event_data}\n\n" if block_given?
              end
            end

            # Capture tool_use block start
            if json_data["type"] == "content_block_start" && json_data["content_block"]["type"] == "tool_use"
              tool_call = json_data["content_block"]
              index = json_data["index"]
              tool_calls << {
                index: index,
                id: tool_call["id"],
                name: tool_call["name"],
                input: ""  # Will be accumulated from delta events
              }
              current_tool_input[index] = ""
            end

            # Accumulate tool input from delta events
            if json_data["type"] == "content_block_delta" && json_data["delta"]["type"] == "input_json_delta"
              index = json_data["index"]
              partial_json = json_data["delta"]["partial_json"]
              current_tool_input[index] ||= ""
              current_tool_input[index] << partial_json
            end

            # Capture message_delta for stop_reason and final usage
            if json_data["type"] == "message_delta"
              stop_reason = json_data["delta"]["stop_reason"] if json_data["delta"]["stop_reason"]
              # Final usage update from message_delta
              if json_data["usage"]
                final_usage = extract_usage(json_data["usage"])
                if usage_data
                  usage_data.add(final_usage)
                else
                  usage_data = final_usage
                end
              end
            end
          end
        end

        # Parse accumulated tool inputs
        tool_calls.each do |tc|
          index = tc[:index]
          if current_tool_input[index] && !current_tool_input[index].empty?
            tc[:input] = safe_parse_json(current_tool_input[index]) || {}
          else
            tc[:input] = {}
          end
          tc.delete(:index)  # Remove the index, we don't need it anymore
        end

        # Log thinking content if present
        if !thinking_content.empty? && Config.logger
          Config.logger.debug "Claude thinking: #{thinking_content}"
        end

        # Check stop_reason for issues
        if stop_reason == "max_tokens"
          Config.logger.warn "Response was truncated due to max_tokens limit. Consider increasing max_tokens."
        end

        {
          content: full_response,
          tool_calls: tool_calls.map do |tc|
            {
              id: tc[:id],
              name: tc[:name],
              parameters: tc[:input]
            }
          end,
          stop_reason: stop_reason,
          usage: usage_data,
          thinking: thinking_content.empty? ? nil : thinking_content,
          model: model
        }
      end

      def extract_usage(usage_hash)
        return nil unless usage_hash

        Usage.new(
          input_tokens: usage_hash["input_tokens"] || 0,
          output_tokens: usage_hash["output_tokens"] || 0,
          cache_read_tokens: usage_hash["cache_read_input_tokens"] || 0,
          cache_creation_tokens: usage_hash["cache_creation_input_tokens"] || 0
        )
      end

      # Retry wrapper with exponential backoff
      # Supports callbacks for observability:
      #   - on_rate_limit: called when rate limit is hit (receives: error, attempt, max_retries, will_retry)
      #   - on_retry: called before each retry (receives: attempt, max_retries, delay, reason)
      def with_retry(options = {})
        retry_config = Config.settings[:retry]
        max_retries = options[:max_retries] || retry_config[:max_retries]
        base_delay = options[:base_delay] || retry_config[:base_delay]
        max_delay = options[:max_delay] || retry_config[:max_delay]
        backoff_factor = options[:backoff_factor] || retry_config[:backoff_factor]

        # Callback hooks for observability
        on_rate_limit = options[:on_rate_limit]
        on_retry = options[:on_retry]

        # Allow disabling retries
        return yield if options[:retry] == false || max_retries == 0

        attempt = 0
        last_error = nil

        loop do
          begin
            return yield
          rescue ApiRateLimitError => e
            last_error = e
            attempt += 1
            will_retry = attempt <= max_retries

            # Fire rate limit callback
            on_rate_limit&.call(e, attempt, max_retries, will_retry)

            if attempt > max_retries
              logger.error "Rate limit exceeded after #{max_retries} retries"
              raise
            end

            # Use retry-after header if available, otherwise calculate backoff
            delay = if e.retry_after?
                      e.retry_after
                    else
                      calculate_delay(attempt, base_delay, max_delay, backoff_factor)
                    end

            # Fire retry callback before sleeping
            on_retry&.call(attempt, max_retries, delay, e.rate_limit_type)

            logger.warn "Rate limited (attempt #{attempt}/#{max_retries}). Retrying in #{delay}s..."
            sleep(delay)
          end
        end
      end

      # Check response status and raise appropriate errors
      def handle_response_status(response)
        case response.code
        when "200"
          # Success - do nothing
        when "429"
          # Rate limit exceeded
          rate_limit_info = parse_rate_limit_headers(response)
          raise ApiRateLimitError.new(
            "Rate limit exceeded: #{response.body}",
            retry_after: rate_limit_info[:retry_after],
            rate_limit_type: rate_limit_info[:type],
            request_id: rate_limit_info[:request_id],
            headers: rate_limit_info[:headers]
          )
        when "500", "502", "503", "504"
          # Server errors - may be retryable
          raise ApiRateLimitError.new(
            "Server error (#{response.code}): #{response.body}",
            retry_after: nil,
            rate_limit_type: :server_error
          )
        when "401"
          raise AuthenticationError.new("Invalid API key", status: :unauthorized)
        else
          raise ApiError.new("API error (#{response.code}): #{response.body}")
        end
      end

      # Parse Anthropic rate limit headers
      def parse_rate_limit_headers(response)
        headers = {}

        # Anthropic rate limit headers
        # https://docs.anthropic.com/en/api/rate-limits
        headers[:requests_limit] = response['anthropic-ratelimit-requests-limit']&.to_i
        headers[:requests_remaining] = response['anthropic-ratelimit-requests-remaining']&.to_i
        headers[:requests_reset] = response['anthropic-ratelimit-requests-reset']
        headers[:tokens_limit] = response['anthropic-ratelimit-tokens-limit']&.to_i
        headers[:tokens_remaining] = response['anthropic-ratelimit-tokens-remaining']&.to_i
        headers[:tokens_reset] = response['anthropic-ratelimit-tokens-reset']

        # Standard retry-after header (in seconds)
        retry_after = response['retry-after']&.to_f

        # Determine rate limit type based on headers
        rate_limit_type = if headers[:tokens_remaining] == 0
                           :tokens
                         elsif headers[:requests_remaining] == 0
                           :requests
                         else
                           :unknown
                         end

        {
          retry_after: retry_after,
          type: rate_limit_type,
          request_id: response['request-id'],
          headers: headers
        }
      end

      # Calculate exponential backoff delay
      def calculate_delay(attempt, base_delay, max_delay, backoff_factor)
        # Exponential backoff with jitter
        delay = base_delay * (backoff_factor ** (attempt - 1))
        # Add jitter (0-25% of delay)
        jitter = delay * rand * 0.25
        [delay + jitter, max_delay].min
      end
    end
  end
end