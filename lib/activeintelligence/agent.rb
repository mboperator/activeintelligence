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
    attr_reader :objective, :messages, :options, :tools, :conversation

    def initialize(objective: nil, options: {}, tools: nil, conversation: nil)
      @objective = objective
      @options = options
      @tools = tools || self.class.tools.map(&:new)
      @conversation = conversation

      # Initialize messages based on memory strategy
      if self.class.memory == :active_record
        raise ConfigurationError, "Conversation required for :active_record memory" unless @conversation
        @messages = load_messages_from_db
      else
        @messages = []
      end

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
      if self.class.memory == :active_record
        persist_message_to_db(message)
      end
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

          Messages::ToolResponse.new(tool_name:, result: tool_output, tool_use_id:, is_error:)
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
      message = Messages::UserMessage.new(content:)
      add_message(message)

      response = call_api
      add_message(response)

      response
    end

    # Handle streaming message requests
    def send_message_streaming(content, options = {}, &block)
      message = Messages::UserMessage.new(content:)
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

          Messages::ToolResponse.new(tool_name:, result: tool_output, tool_use_id:, is_error:)
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
      when :openai
        @api_client = ApiClients::OpenAIClient.new(options)
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
      api_tools = @tools.empty? ? nil : format_tools_for_api

      # Merge options with default caching setting
      api_options = options.merge(
        tools: api_tools,
        enable_prompt_caching: options[:enable_prompt_caching] != false
      )

      # Pass Message objects directly - client will format them
      response = @api_client.call_streaming(@messages, system_prompt, api_options, &block)
      Messages::AgentResponse.new(content: response[:content], tool_calls: response[:tool_calls])
    end

    def call_api
      system_prompt = build_system_prompt
      api_tools = @tools.empty? ? nil : format_tools_for_api

      # Merge options with default caching setting
      api_options = options.merge(
        tools: api_tools,
        enable_prompt_caching: options[:enable_prompt_caching] != false
      )

      # Pass Message objects directly - client will format them
      result = @api_client.call(@messages, system_prompt, api_options)
      AgentResponse.new(content: result[:content], tool_calls: result[:tool_calls])
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

    # ActiveRecord memory strategy methods
    def load_messages_from_db
      return [] unless @conversation.respond_to?(:messages)

      @conversation.messages.order(:created_at).map do |msg|
        # Check if this is a tool response by presence of tool_use_id
        if msg.tool_use_id.present?
          result = msg.content.is_a?(String) ? JSON.parse(msg.content, symbolize_names: true) : msg.content
          Messages::ToolResponse.new(tool_name: msg.tool_name, result: result, tool_use_id: msg.tool_use_id)
        elsif msg.role == 'assistant'
          tool_calls = msg.tool_calls.is_a?(String) ? JSON.parse(msg.tool_calls, symbolize_names: true) : (msg.tool_calls || [])
          Messages::AgentResponse.new(content: msg.content, tool_calls: tool_calls)
        else
          Messages::UserMessage.new(content: msg.content)
        end
      end
    rescue StandardError => e
      raise ConfigurationError, "Failed to load messages from database: #{e.message}"
    end

    def persist_message_to_db(message)
      return unless @conversation.respond_to?(:messages)

      attributes = {
        role: message.role,
        content: message.content
      }

      # Add message-type specific attributes
      case message
      when Messages::AgentResponse
        attributes[:tool_calls] = message.tool_calls.to_json if message.tool_calls&.any?
      when Messages::ToolResponse
        attributes[:tool_name] = message.tool_name
        attributes[:tool_use_id] = message.tool_use_id
        attributes[:content] = message.result.to_json
      end

      @conversation.messages.create!(attributes)
    rescue StandardError => e
      raise ConfigurationError, "Failed to persist message to database: #{e.message}"
    end
  end
end