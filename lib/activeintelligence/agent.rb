require 'pry'

# lib/active_intelligence/agent.rb
module ActiveIntelligence
  class Agent
    class << self
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

      def tool(tool_class)
        @tools ||= []
        @tools << tool_class
      end

      def tools
        @tools || []
      end
    end

    # Instance attributes
    attr_reader :objective, :messages, :options, :tools

    def initialize(objective: nil, options: {}, tools: nil)
      @objective = objective
      @messages = []
      @options = options
      @tools = tools || self.class.tools.map(&:new)
      setup_api_client
    end

    # Main method to send messages that delegates to appropriate handler
    def send_message(message, stream: false, **options, &block)
      if stream && block_given?
        send_message_streaming(message, options, &block)
        process_tool_calls_streaming(&block)
      else
        responses = []
        response = send_message_static(message, options)
        responses << response
        responses += process_tool_calls
        responses.flatten.map(&:content).join("\n\n")
      end
    end

    private

    def add_message(message)
      @messages << message
    end

    def process_tool_calls
      max_iterations = 25  # Prevent infinite loops
      iterations = 0
      responses = []

      # Keep processing tool calls until Claude responds with text only
      while !@messages.last.tool_calls.empty?
        iterations += 1
        if iterations > max_iterations
          raise Error, "Maximum tool call iterations (#{max_iterations}) exceeded. Possible infinite loop."
        end

        tool_calls = @messages.last.tool_calls

        # Execute ALL tool calls from the response
        tool_results = tool_calls.map do |tool_call|
          tool_use_id = tool_call[:id]
          tool_name = tool_call[:name]
          tool_params = tool_call[:parameters]

          # Execute the tool
          tool_output = execute_tool_call(tool_name, tool_params)

          # Check if the tool returned an error
          is_error = tool_output.is_a?(Hash) && tool_output[:error] == true

          ToolResponse.new(tool_name:, result: tool_output, tool_use_id:, is_error:)
        end

        # Add all tool results to message history
        tool_results.each { |tr| add_message(tr) }
        responses += tool_results

        # Get next response from Claude
        response = call_api
        add_message(response)
        responses << response
      end

      responses
    end

    def send_message_static(content, options = {})
      message = UserMessage.new(content:)
      add_message(message)

      response = call_api
      add_message(response)

      response
    end

    # Handle streaming message requests
    def send_message_streaming(content, options = {}, &block)
      message = UserMessage.new(content:)
      add_message(message)

      response = call_streaming_api(&block)
      add_message(response)
      
      response
    end

    def process_tool_calls_streaming(&block)
      max_iterations = 25  # Prevent infinite loops
      iterations = 0

      # Keep processing tool calls until Claude responds with text only
      while !@messages.last.tool_calls.empty?
        iterations += 1
        if iterations > max_iterations
          raise Error, "Maximum tool call iterations (#{max_iterations}) exceeded. Possible infinite loop."
        end

        tool_calls = @messages.last.tool_calls

        # Execute ALL tool calls from the response
        tool_results = tool_calls.map do |tool_call|
          tool_use_id = tool_call[:id]
          tool_name = tool_call[:name]
          tool_params = tool_call[:parameters]

          # Execute the tool
          tool_output = execute_tool_call(tool_name, tool_params)

          # Check if the tool returned an error
          is_error = tool_output.is_a?(Hash) && tool_output[:error] == true

          ToolResponse.new(tool_name:, result: tool_output, tool_use_id:, is_error:)
        end

        # Add all tool results to message history and yield them
        tool_results.each do |tool_response|
          add_message(tool_response)
          yield "\n\n"
          yield tool_response.content
          yield "\n\n"
        end

        # Get next response from Claude
        response = call_streaming_api(&block)
        add_message(response)
      end
    end

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

    def call_streaming_api(&block)
      system_prompt = build_system_prompt
      formatted_messages = format_messages_for_api

      api_tools = @tools.empty? ? nil : format_tools_for_api

      # Merge options with default caching setting
      api_options = options.merge(
        tools: api_tools,
        enable_prompt_caching: options[:enable_prompt_caching] != false
      )

      response = @api_client.call_streaming(formatted_messages, system_prompt, api_options, &block)
      AgentResponse.new(content: response[:content], tool_calls: response[:tool_calls])
    end

    def call_api
      formatted_messages = format_messages_for_api
      system_prompt = build_system_prompt
      api_tools = @tools.empty? ? nil : format_tools_for_api

      # Merge options with default caching setting
      api_options = options.merge(
        tools: api_tools,
        enable_prompt_caching: options[:enable_prompt_caching] != false
      )

      result = @api_client.call(formatted_messages, system_prompt, api_options)
      AgentResponse.new(content: result[:content], tool_calls: result[:tool_calls])
    end

    def format_messages_for_api
      formatted = []
      i = 0

      while i < @messages.length
        msg = @messages[i]

        if msg.is_a?(ToolResponse)
          # Collect consecutive tool responses into a single message
          tool_results = [msg]
          j = i + 1
          while j < @messages.length && @messages[j].is_a?(ToolResponse)
            tool_results << @messages[j]
            j += 1
          end

          # Combine all tool results into one message with multiple content blocks
          formatted << {
            role: "user",
            content: tool_results.map(&:to_api_format)
          }

          i = j  # Skip past all the tool responses we just processed
        elsif msg.is_a?(AgentResponse) && !msg.tool_calls.empty?
          # Use structured format for responses with tool calls
          formatted << {
            role: msg.role,
            content: msg.to_api_format
          }
          i += 1
        else
          # Simple text messages stay the same
          formatted << {
            role: msg.role,
            content: msg.content
          }
          i += 1
        end
      end

      formatted
    end

    def format_tools_for_api
      @tools.map do |tool|
        tool_class = tool.is_a?(Class) ? tool : tool.class
        tool_class.to_json_schema
      end
    end

    # Execute a specific tool call
    def execute_tool_call(tool_name, tool_params)
      # Find matching tool
      tool = @tools.find do |t|
        t.is_a?(Class) ? t.name == tool_name : t.class.name == tool_name
      end

      if tool
        # Execute tool and get result
        tool_instance = tool.is_a?(Class) ? tool.new : tool
        tool_instance.call(tool_params)
      else
        "Tool not found: #{tool_name}"
      end
    end
  end
end