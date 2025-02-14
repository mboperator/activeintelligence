module AgentKit
  class Error < StandardError; end
  class ToolExecutionError < Error; end
  class InvalidParametersError < Error; end
  class LLMError < Error; end
  class PlanningError < Error; end
end
