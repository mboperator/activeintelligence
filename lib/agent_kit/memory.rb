module AgentKit
  class Memory
    def initialize
      @conversation_history = []
      @tool_results = {}
      @context = {}
    end

    def add_interaction(role:, content:)
      @conversation_history << { role: role, content: content, timestamp: Time.now }
    end

    def add_tool_result(tool_name, result)
      @tool_results[tool_name] = result
    end

    def set_context(key, value)
      @context[key] = value
    end

    def get_context(key)
      @context[key]
    end

    def conversation_history
      @conversation_history.dup
    end

    def tool_results
      @tool_results.dup
    end
  end
end