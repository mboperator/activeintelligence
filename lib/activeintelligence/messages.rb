require 'securerandom'

module ActiveIntelligence
  module Messages
    class Message
      attr_accessor :content
      attr_reader   :id, :created_at

      def initialize(content:, created_at: Time.now)
        @id = SecureRandom.uuid
        @content = content
        @created_at = created_at
      end
    end

    class UserMessage < Message
      def role
        "user"
      end
    end

    class ToolResponse < Message
      STATUSES = {
        pending: 'pending',
        complete: 'complete',
        error: 'error'
      }.freeze

      attr_reader :tool_name, :result, :tool_use_id, :is_error, :status, :parameters
      attr_accessor :content

      def initialize(tool_name:, tool_use_id:, parameters: nil, result: nil,
                     is_error: false, status: STATUSES[:pending])
        @tool_name = tool_name
        @tool_use_id = tool_use_id
        @parameters = parameters
        @result = result
        @is_error = is_error
        @status = status
        @content = status == STATUSES[:complete] ? format_tool_result(result) : ''

        super(content: @content)
      end

      def role
        "tool"
      end

      # Status checks
      def pending?
        @status == STATUSES[:pending]
      end

      def complete?
        @status == STATUSES[:complete]
      end

      def error?
        @status == STATUSES[:error]
      end

      # Update this tool response to complete
      def complete!(result)
        @status = result.is_a?(Hash) && result[:error] ? STATUSES[:error] : STATUSES[:complete]
        @result = result
        @is_error = result.is_a?(Hash) && result[:error] == true
        @content = format_tool_result(result)
      end

      private

      def format_tool_result(result)
        return '' if result.nil?

        # Handle error responses
        if result.is_a?(Hash) && result[:error] == true
          error_msg = result[:message] || "Tool execution failed"
          details = result[:details]
          return details ? "#{error_msg}\nDetails: #{details.inspect}" : error_msg
        end

        # Handle success responses - send full data as JSON for Claude to parse
        if result.is_a?(Hash) && result[:data]
          JSON.pretty_generate(result[:data])
        elsif result.is_a?(Array)
          result.map(&:inspect).join("\n")
        else
          result.inspect
        end
      end
    end

    class AgentResponse < Message
      STATES = {
        streaming: "streaming",
        complete: "complete"
      }
      attr_accessor :state
      attr_reader :tool_calls

      def initialize(content:, created_at: nil, tool_calls:)
        @tool_calls = tool_calls
        super(content:, created_at:)
      end

      def role
        "assistant"
      end
    end
  end
end