# lib/active_intelligence/agent.rb
module ActiveIntelligence
  class Agent
    # Agent execution states
    STATES = {
      idle: 'idle',
      awaiting_tool_results: 'awaiting_tool_results',
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
          return build_pending_tools_response
        end

        # Normal completion
        update_state(STATES[:completed])
        [response, *result].flatten.map(&:content).join("\n\n")
      end
    end

    # Resume execution after frontend tool completes
    def continue_with_tool_results(tool_results, stream: false, &block)
      unless @state == STATES[:awaiting_tool_results]
        raise Error, "Cannot continue: agent is in state '#{@state}', expected '#{STATES[:awaiting_tool_results]}'"
      end

      # Update pending tool responses to complete
      Array(tool_results).each do |tr|
        # Find by message_id (from frontend) or tool_use_id (fallback)
        tool_response = if tr[:message_id]
          # Frontend sent DB message ID
          if self.class.memory == :active_record
            db_message = @conversation.messages.find(tr[:message_id])
            # Find in-memory equivalent
            @messages.find { |m| m.is_a?(Messages::ToolResponse) && m.tool_use_id == db_message.tool_use_id }
          end
        else
          # Fallback to tool_use_id
          find_pending_tool_response(tr[:tool_use_id])
        end

        unless tool_response
          raise Error, "Tool response not found for: #{tr.inspect}"
        end

        # Mark complete in memory
        tool_response.complete!(tr[:result])

        # Update DB if using ActiveRecord
        if self.class.memory == :active_record
          db_message = @conversation.messages.find_by(tool_use_id: tool_response.tool_use_id)
          db_message&.complete!(tr[:result])
        end
      end

      # Reload messages from DB to ensure consistency
      if self.class.memory == :active_record
        @messages = load_messages_from_db
      end

      # Check if ALL tools are complete
      if has_pending_tools?
        # Still waiting for more frontend tools
        return build_pending_tools_response
      end

      # All complete - call Claude with ALL results
      update_state(STATES[:idle])

      if stream && block_given?
        # Stream the completed tool results as separate events
        @messages.select { |m| m.is_a?(Messages::ToolResponse) && m.complete? }
                 .last(tool_results.size)
                 .each do |tool_response|
          yield "data: #{JSON.generate({
            type: 'tool_result',
            tool_name: tool_response.tool_name,
            tool_use_id: tool_response.tool_use_id,
            content: tool_response.content
          })}\n\n"
        end

        # Call Claude with completed tool results (streaming)
        response = call_streaming_api(&block)
        add_message(response)

        # Continue processing with streaming (handles any new tool calls)
        process_tool_calls_streaming(&block)
      else
        # Static mode - call Claude with completed tool results
        response = call_api
        add_message(response)
        responses = [response]

        # Process any new tool calls
        result = process_tool_calls
        responses.concat(result) if result

        # Check if we paused again (new tool calls)
        if paused_for_frontend?
          return build_pending_tools_response
        end

        # Completed
        update_state(STATES[:completed])
        responses.flatten.map(&:content).join("\n\n")
      end
    end

    def paused_for_frontend?
      @state == STATES[:awaiting_tool_results]
    end

    private

    # Check if there are any pending tool responses
    def has_pending_tools?
      @messages.any? { |m| m.is_a?(Messages::ToolResponse) && m.pending? }
    end

    # Get all pending tool responses
    def pending_tools
      @messages.select { |m| m.is_a?(Messages::ToolResponse) && m.pending? }
    end

    # Find a specific pending tool response by tool_use_id
    def find_pending_tool_response(tool_use_id)
      @messages.find do |m|
        m.is_a?(Messages::ToolResponse) &&
        m.tool_use_id == tool_use_id &&
        m.pending?
      end
    end

    # Find a tool response by tool_use_id (any status)
    def find_tool_response(tool_use_id)
      @messages.find do |m|
        m.is_a?(Messages::ToolResponse) && m.tool_use_id == tool_use_id
      end
    end

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

        # Create pending ToolResponse messages for ALL tool calls upfront
        tool_calls.each do |tool_call|
          # Skip if already exists (idempotency)
          next if find_tool_response(tool_call[:id])

          tool_response = Messages::ToolResponse.new(
            tool_name: tool_call[:name],
            tool_use_id: tool_call[:id],
            parameters: tool_call[:parameters],
            status: Messages::ToolResponse::STATUSES[:pending]
          )
          add_message(tool_response)
          responses << tool_response
        end

        # Partition tools by execution context
        frontend_tools, backend_tools = partition_tool_calls(tool_calls)

        # Execute backend tools and mark complete
        backend_tools.each do |tool_call|
          tool_response = find_pending_tool_response(tool_call[:id])
          next unless tool_response  # Safety check

          # Execute the tool
          result = execute_tool_call(tool_call[:name], tool_call[:parameters])

          # Update to complete
          tool_response.complete!(result)

          # If using ActiveRecord, update the DB record too
          if self.class.memory == :active_record
            db_message = @conversation.messages.find_by(tool_use_id: tool_call[:id])
            db_message&.complete!(result)
          end
        end

        # Check if we have pending frontend tools
        if has_pending_tools?
          update_state(STATES[:awaiting_tool_results])
          return responses  # Pause - don't call Claude yet
        end

        # All tools complete - call Claude with results
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

        # Create pending ToolResponse messages for ALL tool calls upfront
        tool_calls.each do |tool_call|
          # Skip if already exists (idempotency)
          next if find_tool_response(tool_call[:id])

          tool_response = Messages::ToolResponse.new(
            tool_name: tool_call[:name],
            tool_use_id: tool_call[:id],
            parameters: tool_call[:parameters],
            status: Messages::ToolResponse::STATUSES[:pending]
          )
          add_message(tool_response)
        end

        # Partition tools by execution context
        frontend_tools, backend_tools = partition_tool_calls(tool_calls)

        # Execute backend tools and mark complete
        backend_tools.each do |tool_call|
          tool_response = find_pending_tool_response(tool_call[:id])
          next unless tool_response  # Safety check

          # Execute the tool
          result = execute_tool_call(tool_call[:name], tool_call[:parameters])

          # Update to complete
          tool_response.complete!(result)

          # If using ActiveRecord, update the DB record too
          if self.class.memory == :active_record
            db_message = @conversation.messages.find_by(tool_use_id: tool_call[:id])
            db_message&.complete!(result)
          end

          # Stream the tool result as a separate event
          yield "data: #{JSON.generate({
            type: 'tool_result',
            tool_name: tool_response.tool_name,
            tool_use_id: tool_response.tool_use_id,
            content: tool_response.content
          })}\n\n"
        end

        # Check if we have pending frontend tools
        if has_pending_tools?
          update_state(STATES[:awaiting_tool_results])

          # Build pending tool data with DB message IDs if using ActiveRecord
          pending_tool_data = pending_tools.map do |tr|
            tool_data = {
              tool_use_id: tr.tool_use_id,
              tool_name: tr.tool_name,
              tool_input: tr.parameters
            }

            # Include DB message ID for ActiveRecord memory
            if self.class.memory == :active_record
              db_message = @conversation.messages.find_by(tool_use_id: tr.tool_use_id)
              tool_data[:message_id] = db_message&.id
            end

            tool_data
          end

          # Emit SSE event for frontend tool request
          yield "data: #{JSON.generate({
            type: 'awaiting_tool_results',
            pending_tools: pending_tool_data,
            conversation_id: @conversation&.id
          })}\n\n"

          # Close the stream gracefully
          yield "data: #{JSON.generate({type: 'done'})}\n\n"
          return  # Pause - frontend will resume with continue_with_tool_results
        end

        # All tools complete - call Claude with results
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

    def build_pending_tools_response
      pending_tool_data = pending_tools.map do |tr|
        tool_data = {
          tool_use_id: tr.tool_use_id,
          tool_name: tr.tool_name,
          tool_input: tr.parameters
        }

        # If using ActiveRecord, include DB message ID
        if self.class.memory == :active_record
          db_message = @conversation.messages.find_by(tool_use_id: tr.tool_use_id)
          tool_data[:message_id] = db_message&.id
        end

        tool_data
      end

      {
        status: :awaiting_tool_results,
        pending_tools: pending_tool_data,
        conversation_id: @conversation&.id
      }
    end

    # ActiveRecord memory strategy methods
    def load_messages_from_db
      return [] unless @conversation.respond_to?(:messages)

      @conversation.messages.order(:created_at).map do |msg|
        # STI automatically loads the correct subclass (UserMessage, AssistantMessage, ToolMessage)
        case msg
        when ActiveIntelligence::ToolMessage
          result = msg.content.present? ? JSON.parse(msg.content, symbolize_names: true) : nil
          Messages::ToolResponse.new(
            tool_name: msg.tool_name,
            result: result,
            tool_use_id: msg.tool_use_id,
            status: msg.status,
            parameters: msg.parameters
          )
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
          content: message.content,
          status: 'complete'
        )
      when Messages::AgentResponse
        ActiveIntelligence::AssistantMessage.create!(
          conversation: @conversation,
          content: message.content,
          tool_calls: message.tool_calls&.any? ? message.tool_calls.to_json : nil,
          status: 'complete'
        )
      when Messages::ToolResponse
        ActiveIntelligence::ToolMessage.create!(
          conversation: @conversation,
          content: message.result ? message.result.to_json : nil,
          tool_name: message.tool_name,
          tool_use_id: message.tool_use_id,
          status: message.status,
          parameters: message.parameters
        )
      end
    rescue StandardError => e
      raise ConfigurationError, "Failed to persist message to database: #{e.message}"
    end
  end
end