# lib/activeintelligence/callbacks.rb
require 'securerandom'

module ActiveIntelligence
  # Data structures for callback payloads
  class Session
    attr_reader :id, :agent_class, :created_at
    attr_accessor :ended_at, :total_turns, :total_input_tokens, :total_output_tokens

    def initialize(agent_class:)
      @id = SecureRandom.uuid
      @agent_class = agent_class
      @created_at = Time.now
      @ended_at = nil
      @total_turns = 0
      @total_input_tokens = 0
      @total_output_tokens = 0
    end

    def duration
      return nil unless @ended_at
      @ended_at - @created_at
    end

    def end!
      @ended_at = Time.now
    end

    def to_h
      {
        id: @id,
        agent_class: @agent_class,
        created_at: @created_at,
        ended_at: @ended_at,
        duration: duration,
        total_turns: @total_turns,
        total_input_tokens: @total_input_tokens,
        total_output_tokens: @total_output_tokens
      }
    end
  end

  class Turn
    attr_reader :id, :user_message, :started_at, :session_id
    attr_accessor :ended_at, :usage, :iteration_count

    def initialize(user_message:, session_id:)
      @id = SecureRandom.uuid
      @user_message = user_message
      @session_id = session_id
      @started_at = Time.now
      @ended_at = nil
      @usage = Usage.new
      @iteration_count = 0
    end

    def duration
      return nil unless @ended_at
      @ended_at - @started_at
    end

    def end!
      @ended_at = Time.now
    end

    def to_h
      {
        id: @id,
        session_id: @session_id,
        user_message: @user_message,
        started_at: @started_at,
        ended_at: @ended_at,
        duration: duration,
        usage: @usage.to_h,
        iteration_count: @iteration_count
      }
    end
  end

  class Response
    attr_reader :id, :turn_id, :is_streaming, :started_at
    attr_accessor :ended_at, :content, :usage, :stop_reason, :model, :tool_calls

    def initialize(turn_id:, is_streaming: false)
      @id = SecureRandom.uuid
      @turn_id = turn_id
      @is_streaming = is_streaming
      @started_at = Time.now
      @ended_at = nil
      @content = nil
      @usage = Usage.new
      @stop_reason = nil
      @model = nil
      @tool_calls = []
    end

    def duration
      return nil unless @ended_at
      @ended_at - @started_at
    end

    def end!
      @ended_at = Time.now
    end

    def to_h
      {
        id: @id,
        turn_id: @turn_id,
        is_streaming: @is_streaming,
        started_at: @started_at,
        ended_at: @ended_at,
        duration: duration,
        content: @content,
        usage: @usage.to_h,
        stop_reason: @stop_reason,
        model: @model,
        tool_calls: @tool_calls
      }
    end
  end

  class Chunk
    attr_reader :content, :index, :response_id

    def initialize(content:, index:, response_id:)
      @content = content
      @index = index
      @response_id = response_id
    end

    def to_h
      {
        content: @content,
        index: @index,
        response_id: @response_id
      }
    end
  end

  class Thinking
    attr_reader :response_id, :started_at
    attr_accessor :content, :ended_at

    def initialize(response_id:)
      @response_id = response_id
      @started_at = Time.now
      @content = ""
      @ended_at = nil
    end

    def duration
      return nil unless @ended_at
      @ended_at - @started_at
    end

    def end!
      @ended_at = Time.now
    end

    def to_h
      {
        response_id: @response_id,
        started_at: @started_at,
        ended_at: @ended_at,
        content: @content,
        duration: duration
      }
    end
  end

  class ToolExecution
    attr_reader :name, :tool_class, :input, :started_at, :tool_use_id
    attr_accessor :result, :ended_at, :error

    def initialize(name:, tool_class:, input:, tool_use_id:)
      @name = name
      @tool_class = tool_class
      @input = input
      @tool_use_id = tool_use_id
      @started_at = Time.now
      @ended_at = nil
      @result = nil
      @error = nil
    end

    def duration
      return nil unless @ended_at
      @ended_at - @started_at
    end

    def end!
      @ended_at = Time.now
    end

    def success?
      @error.nil? && @result && !(@result.is_a?(Hash) && @result[:error])
    end

    def to_h
      {
        name: @name,
        tool_class: @tool_class,
        input: @input,
        tool_use_id: @tool_use_id,
        started_at: @started_at,
        ended_at: @ended_at,
        duration: duration,
        result: @result,
        error: @error
      }
    end
  end

  class Usage
    attr_accessor :input_tokens, :output_tokens, :cache_read_tokens, :cache_creation_tokens

    def initialize(input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cache_creation_tokens: 0)
      @input_tokens = input_tokens
      @output_tokens = output_tokens
      @cache_read_tokens = cache_read_tokens
      @cache_creation_tokens = cache_creation_tokens
    end

    def total_tokens
      @input_tokens + @output_tokens
    end

    def add(other_usage)
      return unless other_usage
      @input_tokens += other_usage.input_tokens || 0
      @output_tokens += other_usage.output_tokens || 0
      @cache_read_tokens += other_usage.cache_read_tokens || 0
      @cache_creation_tokens += other_usage.cache_creation_tokens || 0
    end

    def to_h
      {
        input_tokens: @input_tokens,
        output_tokens: @output_tokens,
        total_tokens: total_tokens,
        cache_read_tokens: @cache_read_tokens,
        cache_creation_tokens: @cache_creation_tokens
      }
    end
  end

  class Iteration
    attr_reader :number, :tool_calls_count, :turn_id, :timestamp

    def initialize(number:, tool_calls_count:, turn_id:)
      @number = number
      @tool_calls_count = tool_calls_count
      @turn_id = turn_id
      @timestamp = Time.now
    end

    def to_h
      {
        number: @number,
        tool_calls_count: @tool_calls_count,
        turn_id: @turn_id,
        timestamp: @timestamp
      }
    end
  end

  class ErrorContext
    attr_reader :error, :context

    def initialize(error:, context: {})
      @error = error
      @context = context
    end

    def error_class
      @error.class.to_s
    end

    def message
      @error.message
    end

    def backtrace
      @error.backtrace
    end

    def to_h
      {
        error_class: error_class,
        message: message,
        backtrace: backtrace&.first(10),
        context: @context
      }
    end
  end

  class StopEvent
    attr_reader :reason, :details

    REASONS = {
      max_turns: :max_turns,
      user_stop: :user_stop,
      error: :error,
      complete: :complete,
      frontend_pause: :frontend_pause,
      rate_limit: :rate_limit  # Added for rate limit exhaustion
    }.freeze

    def initialize(reason:, details: {})
      @reason = reason
      @details = details
    end

    def to_h
      {
        reason: @reason,
        details: @details
      }
    end
  end

  # Rate limit event - fired when API returns 429 or similar
  class RateLimitEvent
    attr_reader :error, :attempt, :max_retries, :retry_after, :rate_limit_type,
                :request_id, :will_retry, :timestamp

    def initialize(error:, attempt:, max_retries:, will_retry:)
      @error = error
      @attempt = attempt
      @max_retries = max_retries
      @retry_after = error.retry_after
      @rate_limit_type = error.rate_limit_type
      @request_id = error.request_id
      @will_retry = will_retry
      @timestamp = Time.now
    end

    def to_h
      {
        attempt: @attempt,
        max_retries: @max_retries,
        retry_after: @retry_after,
        rate_limit_type: @rate_limit_type,
        request_id: @request_id,
        will_retry: @will_retry,
        message: @error.message,
        timestamp: @timestamp
      }
    end
  end

  # Retry event - fired before each retry attempt
  class RetryEvent
    attr_reader :attempt, :max_retries, :delay, :reason, :timestamp

    def initialize(attempt:, max_retries:, delay:, reason:)
      @attempt = attempt
      @max_retries = max_retries
      @delay = delay
      @reason = reason
      @timestamp = Time.now
    end

    def remaining_retries
      @max_retries - @attempt
    end

    def to_h
      {
        attempt: @attempt,
        max_retries: @max_retries,
        remaining_retries: remaining_retries,
        delay: @delay,
        reason: @reason,
        timestamp: @timestamp
      }
    end
  end

  # Callbacks module to be included in Agent
  module Callbacks
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      HOOK_NAMES = %i[
        on_session_start
        on_session_end
        on_turn_start
        on_turn_end
        on_response_start
        on_response_end
        on_response_chunk
        on_thinking_start
        on_thinking_end
        on_tool_start
        on_tool_end
        on_tool_error
        on_message_added
        on_iteration
        on_error
        on_stop
        on_rate_limit
        on_retry
      ].freeze

      def callbacks
        @callbacks ||= {}
      end

      # Generate DSL methods for each hook
      HOOK_NAMES.each do |hook_name|
        define_method(hook_name) do |method_name = nil, &block|
          callbacks[hook_name] ||= []
          if block
            callbacks[hook_name] << block
          elsif method_name
            callbacks[hook_name] << method_name
          end
        end
      end

      def inherited(subclass)
        super
        # Copy parent callbacks to subclass
        subclass.instance_variable_set(:@callbacks, callbacks.transform_values(&:dup))
      end
    end

    # Instance methods for triggering callbacks
    def trigger_callback(hook_name, *args)
      handlers = self.class.callbacks[hook_name] || []
      handlers.each do |handler|
        if handler.is_a?(Symbol)
          send(handler, *args)
        else
          instance_exec(*args, &handler)
        end
      rescue StandardError => e
        # Don't let callback errors break the main flow
        Config.logger&.error("Callback error in #{hook_name}: #{e.message}")
      end
    end
  end
end
