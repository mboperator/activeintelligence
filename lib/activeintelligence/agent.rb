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
                   # For streaming, we need special handling for tool calls
                   streaming_with_tool_processing(formatted_messages, system_prompt, options.merge(tools: api_tools), &block)
                 else
                   @api_client.call(formatted_messages, system_prompt, options.merge(tools: api_tools))
                 end

      # Process tool calls if needed (only for non-streaming)
      response = process_tool_calls(response) if !stream && contains_tool_calls?(response)

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
          content += "\n\nTool Result (#{tool_name}):\n#{format_tool_result(result)}"
        else
          content += "\n\nTool not found: #{tool_name}"
        end
      end

      content
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
        result = tool_instance.call(tool_params)
        return result
      else
        return "Tool not found: #{tool_name}"
      end
    end

    # Handle streaming responses with tool call processing
    def streaming_with_tool_processing(messages, system_prompt, options, &block)
      full_response = ""
      current_chunk = ""
      tool_call_detected = false
      tool_call_name = nil
      tool_call_params = {}
      
      @api_client.call_streaming(messages, system_prompt, options) do |chunk|
        # Check if chunk contains a tool call
        if chunk.start_with?('[') && chunk.include?(':')
          # Extract tool call information
          match_data = chunk.match(/\[(.*?):(\{.*\})\]/)
          if match_data
            tool_call_detected = true
            tool_call_name = match_data[1]
            begin
              tool_call_params = JSON.parse(match_data[2])
            rescue JSON::ParserError
              tool_call_params = {}
            end
            
            # Get display name for the tool (without namespace)
            display_name = tool_call_name.to_s.split('::').last
            
            # Let user know we're executing a tool
            yield "\nExecuting tool: #{display_name}...\n"
            
            # Execute the tool
            tool_result = execute_tool_call(tool_call_name, tool_call_params)
            
            # Add the tool result to the full response with better formatting
            result_text = "Result: #{format_tool_result(tool_result)}\n\n"
            full_response += result_text
            yield result_text
            
            # Continue the conversation with the tool result
            yield "Continuing conversation with tool result...\n"
            continue_conversation_with_tool_result(messages, system_prompt, tool_call_name, tool_call_params, tool_result, options, &block)
          else
            # Pass through regular chunk
            full_response += chunk
            yield chunk if block_given?
          end
        else
          # Pass through regular chunk
          full_response += chunk
          yield chunk if block_given?
        end
      end
      
      full_response
    end
    
    # Format the tool result for display
    def format_tool_result(result)
      if result.is_a?(Hash) && result[:data] && result[:data].is_a?(Hash)
        result[:data].values.first
      elsif result.is_a?(Hash) && result[:data]
        result[:data]
      elsif result.is_a?(Array)
        result.map(&:inspect).join("\n")
      else
        result.inspect
      end
    end
    
    # Continue the conversation with the tool result
    def continue_conversation_with_tool_result(messages, system_prompt, tool_name, tool_params, tool_result, options, &block)
      # Format the tool name for display
      display_name = tool_name.to_s.split('::').last
      
      # Create a message for the tool usage and result
      tool_result_content = "Tool #{display_name} returned: #{format_tool_result(tool_result)}\n\nPlease continue your response based on this information."
      
      # Add an assistant message to indicate tool usage and a user message with the result
      updated_messages = messages + [
        { role: 'assistant', content: "I'll use the #{display_name} tool." },
        { role: 'user', content: tool_result_content }
      ]
      
      # Make another API call to continue the conversation
      @api_client.call_streaming(updated_messages, system_prompt, options) do |chunk|
        yield chunk if block_given?
      end
    end
  end
end