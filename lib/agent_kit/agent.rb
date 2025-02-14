module AgentKit
  class Agent
    class << self
      def objective
        raise NotImplementedError, "#{self.name} must implement .objective"
      end

      def tools
        raise NotImplementedError, "#{self.name} must implement .tools"
      end
    end

    def initialize(llm_client = nil)
      @llm_client = llm_client || default_llm_client
      @memory = Memory.new
      @logger = Logger.instance
    end

    def execute_mission(mission)
      # 1. Parse the mission
      # 2. Plan steps using available tools
      # 3. Execute each step
      plan = create_plan(mission)
      execute_plan(plan)
    end

    private

    def create_plan(mission)
      prompt = generate_planning_prompt(mission)
      response = @llm_client.complete(prompt)
      parse_plan(response)
    end

    def execute_plan(plan)
      plan.steps.map do |step|
        tool = find_tool(step.tool_name)
        tool.new.execute(step.parameters)
      end
    end

    def generate_planning_prompt(mission)
      tools_description = self.class.tools.map do |tool|
        <<~TOOL
          Tool: #{tool.name}
          Type: #{tool.type}
          Parameters: #{tool.parameters.inspect}
          Description: #{tool.description}
        TOOL
      end.join("\n\n")

      <<~PROMPT
        Objective: #{self.class.objective}
        Mission: #{mission}

        Available Tools:
        #{tools_description}

        Create a plan to accomplish this mission using the available tools.
        Format your response as a JSON array of steps, where each step has:
        - tool_name: string
        - parameters: object
        - reason: string explaining why this step is necessary
      PROMPT
    end

    def parse_plan(response)
      # Parse the LLM's JSON response into a Plan object
      # Implementation depends on your LLM's response format
    end

    def find_tool(tool_name)
      self.class.tools.find { |t| t.name == tool_name }
    end

    def default_llm_client
      # Implement your default LLM client here
      # Could be Anthropic, OpenAI, etc.
    end
  end
end