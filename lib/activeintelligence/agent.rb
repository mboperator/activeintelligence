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
      end

      # DSL methods
      def model(model_name)
        @model_name = model_name
      end

      def memory(memory_type)
        @memory_type = memory_type
      end

      def identity(identity_text = nil)
        if identity_text.nil?
          @identity || ""
        else
          @identity = identity_text
        end
      end

      # Getters with fallbacks
      def model_name
        @model_name
      end

      def memory_type
        @memory_type
      end
    end

    # Instance attributes
    attr_reader :objective, :messages, :options

    # Initialize with optional parameters
    def initialize(objective: nil, options: {})
      @objective = objective
      @messages = []
      @options = options
      setup_api_client
    end

    # Main method to send messages with streaming support
    def send_message(message, stream: false, **options, &block)
      add_message('user', message)

      # Prepare system prompt
      system_prompt = build_system_prompt

      # Format messages for API
      formatted_messages = format_messages_for_api

      # Call API based on streaming option
      response = if stream && block_given?
                   @api_client.call_streaming(formatted_messages, system_prompt, options, &block)
                 else
                   @api_client.call(formatted_messages, system_prompt, options)
                 end

      # Save response to history
      add_message('assistant', response)

      # Return the response
      response
    end

    private

    def setup_api_client
      case self.class.model_name
      when :claude
        @api_client = ApiClients::ClaudeClient.new(options)
      else
        raise ConfigurationError, "Unsupported model: #{self.class.model_name}"
      end
    end

    def build_system_prompt
      prompt = self.class.identity.to_s
      prompt += "\n\nYour objective: #{@objective}" if @objective
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
  end
end