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
    def role
      "user"
    end
  end

  class AgentResponse < Message
    STATES = {
      streaming: "streaming",
      complete: "complete"
    }
    attr_accessor :state

    def role
      "assistant"
    end
  end
end