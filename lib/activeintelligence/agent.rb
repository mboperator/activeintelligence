# lib/active_intelligence/agent.rb
module ActiveIntelligence
  class Agent
    # Agent execution states
    STATES = {
      idle: 'idle',
      awaiting_frontend_tool: 'awaiting_frontend_tool',
      completed: 'completed'
    }.freeze

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
    attr_reader :objective, :messages, :options, :tools, :conversation, :state

    def initialize(objective: nil, options: {}, tools: nil, conversation: nil)
      @objective = objective
      @options = options
      @tools = tools || self.class.tools.map(&:new)
      @conversation = conversation

      # Initialize messages based on memory strategy
      if self.class.memory == :active_record
        raise ConfigurationError, "Conversation required for :active_record memory" unless @conversation
        load_state_from_conversation
        @messages = load_messages_from_db
      else
        @messages = []
        @state = STATES[:idle]
      end

      setup_api_client
    end

    # Main method to send messages that delegates to appropriate handler
    def send_message(message, stream: false, **options, &block)
      # Save agent class name to conversation for reconstruction
      persist_agent_class if @conversation

      if stream && block_given?
        send_message_streaming(message, options, &block)
        process_tool_calls_streaming(&block)
      else
        response = send_message_static(message, options)
        result = process_tool_calls

        # Check if we paused for frontend tools
        if paused_for_frontend?
          return build_frontend_response
        end

        # Normal completion
        update_state(STATES[:completed])
        [response, *result].flatten.map(&:content).join("\n\n")
      end
    end

    # Resume execution after frontend tool completes
    def continue_with_tool_results(tool_results, stream: false, &block)
      unless @state == STATES[:awaiting_frontend_tool]
        raise Error, "Cannot continue: agent is in state '#{@state}', expected '#{STATES[:awaiting_frontend_tool]}'"
      end

      # Add tool results to message history
      Array(tool_results).each do |result|
        tool_response = Messages::ToolResponse.new(
          tool_name: result[:tool_name],
          result: result[:result],
          tool_use_id: result[:tool_use_id],
          is_error: result[:is_error] || false
        )
        add_message(tool_response)
      end

      # Clear pending frontend tools
      clear_pending_frontend_tools

      # Resume processing (will call Claude with tool results)
      update_state(STATES[:idle])

      if stream && block_given?
        # Stream the tool results that were just added
        @messages.select { |m| m.is_a?(Messages::ToolResponse) }
                 .last(tool_results.size)
                 .each do |tool_response|
          yield "\n\n"
          yield tool_response.content
          yield "\n\n"
        end

        # Continue processing with streaming
        process_tool_calls_streaming(&block)
      else
        # Static mode
        result = process_tool_calls

        # Check if we paused again
        if paused_for_frontend?
          return build_frontend_response
        end

        # Completed
        update_state(STATES[:completed])
        result.flatten.map(&:content).join("\n\n")
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

        # Separate frontend and backend tools
        frontend_tools, backend_tools = partition_tool_calls(tool_calls)

        # If we have frontend tools, pause execution
        if frontend_tools.any?
          store_pending_frontend_tools(frontend_tools)
          update_state(STATES[:awaiting_frontend_tool])
          return responses  # Pause here
        end

        # Execute backend tools only
        tool_results = backend_tools.map do |tool_call|
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

        # Separate frontend and backend tools
        frontend_tools, backend_tools = partition_tool_calls(tool_calls)

        # Execute backend tools first and stream their results
        backend_tool_results = backend_tools.map do |tool_call|
          tool_use_id = tool_call[:id]
          tool_name = tool_call[:name]
          tool_params = tool_call[:parameters]

          # Execute the tool
          tool_output = execute_tool_call(tool_name, tool_params)

          # Check if the tool returned an error
          is_error = tool_output.is_a?(Hash) && tool_output[:error] == true

          Messages::ToolResponse.new(tool_name:, result: tool_output, tool_use_id:, is_error:)
        end

        # Add backend tool results to message history and yield them
        backend_tool_results.each do |tool_response|
          add_message(tool_response)
          yield "\n\n"
          yield tool_response.content
          yield "\n\n"
        end

        # If we have frontend tools, pause execution and emit special event
        if frontend_tools.any?
          store_pending_frontend_tools(frontend_tools)
          update_state(STATES[:awaiting_frontend_tool])

          # Emit SSE event for frontend tool request
          yield "event: frontend_tool_request\n"
          yield "data: #{JSON.generate({
            status: 'awaiting_frontend_tool',
            tools: frontend_tools,
            conversation_id: @conversation&.id
          })}\n\n"

          # Close the stream gracefully
          yield "data: [DONE]\n\n"
          return  # Pause here - frontend will resume with new request
        end

        # Get next response from Claude (only if no frontend tools)
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

    # Partition tools by execution context
    def partition_tool_calls(tool_calls)
      frontend_tools = []
      backend_tools = []

      tool_calls.each do |tool_call|
        tool = find_tool(tool_call[:name])

        if tool&.class&.frontend?
          frontend_tools << tool_call
        else
          backend_tools << tool_call
        end
      end

      [frontend_tools, backend_tools]
    end

    def find_tool(tool_name)
      @tools.find do |t|
        tool_class = t.is_a?(Class) ? t : t.class
        tool_class.name == tool_name
      end
    end

    # State management methods
    def load_state_from_conversation
      @state = @conversation.agent_state || STATES[:idle]
    end

    def update_state(new_state)
      @state = new_state
      @conversation&.update(agent_state: new_state)
    end

    def persist_agent_class
      return if @conversation.agent_class_name == self.class.name
      @conversation.update(agent_class_name: self.class.name)
    end

    def paused_for_frontend?
      @state == STATES[:awaiting_frontend_tool]
    end

    def store_pending_frontend_tools(tools)
      @conversation&.update(pending_frontend_tools: tools)
    end

    def clear_pending_frontend_tools
      @conversation&.update(pending_frontend_tools: nil)
    end

    def build_frontend_response
      {
        status: :awaiting_frontend_tool,
        tools: @conversation.pending_frontend_tools,
        conversation_id: @conversation.id
      }
    end

    # ActiveRecord memory strategy methods
    def load_messages_from_db
      return [] unless @conversation.respond_to?(:messages)

      @conversation.messages.order(:created_at).map do |msg|
        # STI automatically loads the correct subclass (UserMessage, AssistantMessage, ToolMessage)
        case msg
        when ActiveIntelligence::ToolMessage
          result = msg.content.is_a?(String) ? JSON.parse(msg.content, symbolize_names: true) : msg.content
          Messages::ToolResponse.new(tool_name: msg.tool_name, result: result, tool_use_id: msg.tool_use_id)
        when ActiveIntelligence::AssistantMessage
          tool_calls = msg.tool_calls.is_a?(String) ? JSON.parse(msg.tool_calls, symbolize_names: true) : (msg.tool_calls || [])
          Messages::AgentResponse.new(content: msg.content, tool_calls: tool_calls)
        when ActiveIntelligence::UserMessage
          Messages::UserMessage.new(content: msg.content)
        end
      end
    rescue StandardError => e
      raise ConfigurationError, "Failed to load messages from database: #{e.message}"
    end

    def persist_message_to_db(message)
      return unless @conversation.respond_to?(:messages)

      # Use STI classes based on message type
      case message
      when Messages::UserMessage
        ActiveIntelligence::UserMessage.create!(
          conversation: @conversation,
          content: message.content
        )
      when Messages::AgentResponse
        ActiveIntelligence::AssistantMessage.create!(
          conversation: @conversation,
          content: message.content,
          tool_calls: message.tool_calls&.any? ? message.tool_calls.to_json : nil
        )
      when Messages::ToolResponse
        ActiveIntelligence::ToolMessage.create!(
          conversation: @conversation,
          content: message.result.to_json,
          tool_name: message.tool_name,
          tool_use_id: message.tool_use_id
        )
      end
    rescue StandardError => e
      raise ConfigurationError, "Failed to persist message to database: #{e.message}"
    end
  end
end