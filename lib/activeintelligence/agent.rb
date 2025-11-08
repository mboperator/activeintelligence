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
      last_message = @messages.last
      if last_message.tool_calls.empty?
        []
      else
        # Handle structured tool calls from API response
        tool_call = last_message.tool_calls.first
        tool_name = tool_call[:name]
        tool_params = tool_call[:parameters]

        # Execute the tool
        tool_output = execute_tool_call(tool_name, tool_params)
        tool_response = ToolResponse.new(tool_name:, result: tool_output)
        add_message(tool_response)
        response = call_api
        add_message(response)

        [tool_response, response]
      end
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
      last_message = @messages.last

      if last_message.tool_calls.empty?
        []
      else
        # Handle structured tool calls from API response
        tool_call = last_message.tool_calls.first
        tool_name = tool_call[:name]
        tool_params = tool_call[:parameters]

        # Execute the tool
        tool_output = execute_tool_call(tool_name, tool_params)
        tool_response = ToolResponse.new(tool_name:, result: tool_output)
        add_message(tool_response)

        yield "\n\n"
        yield tool_response.content
        yield "\n\n"

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

      response = @api_client.call_streaming(formatted_messages, system_prompt, options.merge(tools: api_tools), &block)
      AgentResponse.new(content: response[:content], tool_calls: response[:tool_calls])
    end

    def call_api
      formatted_messages = format_messages_for_api
      system_prompt = build_system_prompt
      api_tools = @tools.empty? ? nil : format_tools_for_api

      result = @api_client.call(formatted_messages, system_prompt, options.merge(tools: api_tools))
      AgentResponse.new(content: result[:content], tool_calls: result[:tool_calls])
    end

    def format_messages_for_api
      @messages.map do |msg|
        { role: msg.role, content: msg.content }
      end
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
        case msg.role
        when 'user'
          UserMessage.new(content: msg.content)
        when 'assistant'
          tool_calls = msg.tool_calls.is_a?(String) ? JSON.parse(msg.tool_calls) : (msg.tool_calls || [])
          AgentResponse.new(content: msg.content, tool_calls: tool_calls)
        when 'tool'
          result = msg.content.is_a?(String) ? JSON.parse(msg.content) : msg.content
          ToolResponse.new(tool_name: msg.tool_name, result: result)
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
      when AgentResponse
        attributes[:tool_calls] = message.tool_calls.to_json if message.tool_calls&.any?
      when ToolResponse
        attributes[:tool_name] = message.tool_name
        attributes[:content] = message.result.to_json
      end

      @conversation.messages.create!(attributes)
    rescue StandardError => e
      raise ConfigurationError, "Failed to persist message to database: #{e.message}"
    end
  end
end