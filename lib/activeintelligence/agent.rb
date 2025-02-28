# lib/active_intelligence/agent.rb
module ActiveIntelligence
  class Agent
    # Class attributes and methods for DSL
    class << self
      # Setup inheritance hooks for subclasses
      def inherited(subclass)
        subclass.instance_variable_set(:@model_name, nil)
        subclass.instance_variable_set(:@memory_type, nil)
        subclass.instance_variable_set(:@identity, nil)
        subclass.instance_variable_set(:@tools, [])
      end

      # DSL methods
      def model(model_name = nil)
        @model_name = model_name if model_name
        @model_name
      end

      def memory(memory_type = nil)
        @memory_type = memory_type if memory_type
        @memory_type
      end

      def identity(identity_text = nil)
        @identity = identity_text if identity_text
        @identity
      end

      # Tool registration
      def tool(tool_class)
        @tools ||= []
        @tools << tool_class
      end

      # Access registered tools
      def tools
        @tools || []
      end

      # Remove separate getters as they're now built into the DSL methods
    end

    # Instance attributes
    attr_reader :objective, :messages, :options, :tools

    # Initialize with optional parameters
    def initialize(objective: nil, options: {}, tools: nil)
      @objective = objective
      @messages = []
      @options = options
      @tools = tools || self.class.tools.map(&:new)
      setup_api_client
    end

    # Main method to send messages with streaming support
    def send_message(message, stream: false, **options, &block)
      add_message('user', message)

      # Prepare system prompt
      system_prompt = build_system_prompt

      # Format messages for API
      formatted_messages = format_messages_for_api

      # Prepare tools for API
      api_tools = @tools.empty? ? nil : format_tools_for_api

      # Call API based on streaming option
      response = if stream && block_given?
                   @api_client.call_streaming(formatted_messages, system_prompt, options.merge(tools: api_tools), &block)
                 else
                   @api_client.call(formatted_messages, system_prompt, options.merge(tools: api_tools))
                 end

      # Process tool calls if needed
      response = process_tool_calls(response) if contains_tool_calls?(response)

      # Save response to history
      add_message('assistant', response)

      # Return the response
      response
    end

    private

    def setup_api_client
      case self.class.model
      when :claude
        @api_client = ApiClients::ClaudeClient.new(options)
      else
        raise ConfigurationError, "Unsupported model: #{self.class.model}"
      end
    end

    def build_system_prompt
      prompt = self.class.identity.to_s
      prompt = "" if prompt.nil? # Ensure we have at least an empty string
      prompt += "\n\nYour objective: #{@objective}" if @objective

      # Add information about available tools if present
      unless @tools.empty?
        prompt += "\n\nYou have access to the following tools:\n"
        @tools.each do |tool|
          tool_class = tool.is_a?(Class) ? tool : tool.class
          prompt += "- #{tool_class.name}: #{tool_class.description}\n"
        end
      end

      prompt
    end

    def add_message(role, content)
      @messages << { role: role, content: content }
    end

    def format_messages_for_api
      @messages.map do |msg|
        { role: msg[:role], content: msg[:content] }
      end
    end

    def format_tools_for_api
      @tools.map do |tool|
        tool_class = tool.is_a?(Class) ? tool : tool.class
        tool_class.to_json_schema
      end
    end

    def contains_tool_calls?(response)
      response.is_a?(Hash) && response[:tool_calls].is_a?(Array) && !response[:tool_calls].empty?
    end

    def process_tool_calls(response)
      return response unless contains_tool_calls?(response)

      content = response[:content] || ""

      # Process each tool call
      response[:tool_calls].each do |tool_call|
        tool_name = tool_call[:name]
        tool_params = tool_call[:parameters]

        # Find matching tool
        tool = @tools.find do |t|
          t.is_a?(Class) ? t.name == tool_name : t.class.name == tool_name
        end

        if tool
          # Execute tool and get result
          tool_instance = tool.is_a?(Class) ? tool.new : tool
          result = tool_instance.call(tool_params)

          # Add tool result to content
          content += "\n\nTool Result (#{tool_name}):\n#{result.inspect}"
        else
          content += "\n\nTool not found: #{tool_name}"
        end
      end

      content
    end
  end
end