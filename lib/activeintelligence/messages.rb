require 'securerandom'

module ActiveIntelligence
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
    attr_accessor :result, :content, :tool_name
    def initialize(tool_name:, result:)
      @tool_name = tool_name
      @result = result

      super(content: tool_response_content)
    end
    def role
      "user"
    end

    def tool_response_content
      "Tool #{tool_name} returned: #{format_tool_result(result)}"
    end

    private

    def format_tool_result(result)
      if result.is_a?(Hash) && result[:data] && result[:data].is_a?(Hash)
        result[:data].values.first
      elsif result.is_a?(Hash) && result[:data]
        result[:data]
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
    attr_accessor :state, :tool_calls

    def initialize(content:, created_at: nil, tool_calls:)
      @tool_calls = tool_calls
      super(content:, created_at:)
    end

    def role
      "assistant"
    end
  end
end