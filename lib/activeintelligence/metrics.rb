# lib/activeintelligence/metrics.rb
module ActiveIntelligence
  # Tracks metrics for an agent's lifecycle including API calls, tokens, latency, and errors
  class Metrics
    attr_reader :total_messages, :total_user_messages, :total_agent_messages,
                :total_tokens, :total_input_tokens, :total_output_tokens,
                :total_api_calls, :total_tool_calls, :total_errors,
                :cached_tokens_saved, :started_at

    def initialize
      @total_messages = 0
      @total_user_messages = 0
      @total_agent_messages = 0
      @total_tokens = 0
      @total_input_tokens = 0
      @total_output_tokens = 0
      @total_api_calls = 0
      @total_tool_calls = 0
      @total_errors = 0
      @cached_tokens_saved = 0
      @api_latencies = []
      @tool_latencies = []
      @started_at = Time.now
      @stop_reasons = Hash.new(0)
      @tool_executions = Hash.new(0)
      @error_types = Hash.new(0)
    end

    # Record a user message
    def record_user_message
      @total_messages += 1
      @total_user_messages += 1
    end

    # Record an agent message
    def record_agent_message
      @total_messages += 1
      @total_agent_messages += 1
    end

    # Record an API call with duration and token usage
    def record_api_call(duration_ms, usage = nil, stop_reason = nil)
      @total_api_calls += 1
      @api_latencies << duration_ms if duration_ms

      if usage
        @total_tokens += usage[:total_tokens] if usage[:total_tokens]
        @total_input_tokens += usage[:input_tokens] if usage[:input_tokens]
        @total_output_tokens += usage[:output_tokens] if usage[:output_tokens]

        # Track cached tokens (Claude-specific)
        if usage[:cache_read_input_tokens]
          @cached_tokens_saved += usage[:cache_read_input_tokens]
        end
      end

      @stop_reasons[stop_reason] += 1 if stop_reason
    end

    # Record a tool call with duration
    def record_tool_call(tool_name, duration_ms = nil, success = true)
      @total_tool_calls += 1
      @tool_latencies << duration_ms if duration_ms
      @tool_executions[tool_name] += 1
      record_error("tool_execution_error") unless success
    end

    # Record an error
    def record_error(error_type)
      @total_errors += 1
      @error_types[error_type] += 1
    end

    # Calculated metrics
    def average_api_latency
      return 0.0 if @api_latencies.empty?
      @api_latencies.sum.to_f / @api_latencies.length
    end

    def p95_api_latency
      return 0.0 if @api_latencies.empty?
      sorted = @api_latencies.sort
      index = (sorted.length * 0.95).ceil - 1
      sorted[index] || 0.0
    end

    def p99_api_latency
      return 0.0 if @api_latencies.empty?
      sorted = @api_latencies.sort
      index = (sorted.length * 0.99).ceil - 1
      sorted[index] || 0.0
    end

    def average_tool_latency
      return 0.0 if @tool_latencies.empty?
      @tool_latencies.sum.to_f / @tool_latencies.length
    end

    def cache_hit_rate
      return 0.0 if @total_input_tokens.zero?
      (@cached_tokens_saved.to_f / @total_input_tokens * 100).round(2)
    end

    def estimated_cost_usd(model = "claude-3-opus-20240229")
      # Pricing as of 2024 (per million tokens)
      pricing = case model
      when /opus/
        { input: 15.0, output: 75.0, cache_write: 18.75, cache_read: 1.50 }
      when /sonnet/
        { input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.30 }
      when /haiku/
        { input: 0.25, output: 1.25, cache_write: 0.30, cache_read: 0.03 }
      else
        { input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.30 }
      end

      input_cost = (@total_input_tokens / 1_000_000.0) * pricing[:input]
      output_cost = (@total_output_tokens / 1_000_000.0) * pricing[:output]
      cache_cost = (@cached_tokens_saved / 1_000_000.0) * pricing[:cache_read]

      total = input_cost + output_cost - cache_cost
      total.round(4)
    end

    def uptime_seconds
      (Time.now - @started_at).round(2)
    end

    # Export all metrics as a hash
    def to_h
      {
        messages: {
          total: @total_messages,
          user: @total_user_messages,
          agent: @total_agent_messages
        },
        tokens: {
          total: @total_tokens,
          input: @total_input_tokens,
          output: @total_output_tokens,
          cached: @cached_tokens_saved,
          cache_hit_rate_percent: cache_hit_rate
        },
        api_calls: {
          total: @total_api_calls,
          average_latency_ms: average_api_latency.round(2),
          p95_latency_ms: p95_api_latency.round(2),
          p99_latency_ms: p99_api_latency.round(2)
        },
        tool_calls: {
          total: @total_tool_calls,
          average_latency_ms: average_tool_latency.round(2),
          by_tool: @tool_executions
        },
        errors: {
          total: @total_errors,
          by_type: @error_types
        },
        stop_reasons: @stop_reasons,
        uptime_seconds: uptime_seconds,
        estimated_cost_usd: estimated_cost_usd
      }
    end

    # Pretty print metrics
    def to_s
      <<~METRICS
        ActiveIntelligence Metrics
        ===========================
        Messages: #{@total_messages} (#{@total_user_messages} user, #{@total_agent_messages} agent)
        Tokens: #{@total_tokens} total (#{@total_input_tokens} input, #{@total_output_tokens} output)
        Cached: #{@cached_tokens_saved} tokens (#{cache_hit_rate}% hit rate)
        API Calls: #{@total_api_calls} (avg: #{average_api_latency.round(2)}ms, p95: #{p95_api_latency.round(2)}ms)
        Tool Calls: #{@total_tool_calls} (avg: #{average_tool_latency.round(2)}ms)
        Errors: #{@total_errors}
        Estimated Cost: $#{estimated_cost_usd}
        Uptime: #{uptime_seconds}s
      METRICS
    end

    # Reset all metrics
    def reset!
      initialize
    end
  end
end
