module ActiveIntelligence
  module ConversationManageable
    extend ActiveSupport::Concern

    included do
      # Include ActionController::Live for streaming support if needed
      # include ActionController::Live
    end

    private

    # Find or create a conversation for the current context
    # Override this method to customize conversation lookup logic
    def current_conversation
      @current_conversation ||= find_or_create_conversation
    end

    # Find conversation by ID with proper scoping
    def find_conversation(id)
      conversation_scope.find(id)
    end

    # Create a new conversation
    def create_conversation(agent_class:, objective: nil, **attributes)
      conversation_scope.create!(
        agent_class: agent_class,
        objective: objective,
        **attributes
      )
    end

    # Get the scope for conversations (override to add user scoping, etc.)
    # Example: current_user.active_intelligence_conversations
    def conversation_scope
      ActiveIntelligence::Conversation.all
    end

    # Initialize an agent for the current conversation
    def initialize_agent(conversation = current_conversation, **options)
      conversation.agent(**options)
    end

    # Send a message to the agent (non-streaming)
    def send_agent_message(message, conversation: current_conversation, **options)
      agent = initialize_agent(conversation, options: options)
      agent.send_message(message)
    end

    # Send a message to the agent (streaming)
    # Requires ActionController::Live to be included
    def send_agent_message_streaming(message, conversation: current_conversation, **options, &block)
      raise NotImplementedError, "Include ActionController::Live to use streaming" unless respond_to?(:stream)

      agent = initialize_agent(conversation, options: options)

      response.headers['Content-Type'] = 'text/event-stream'
      response.headers['X-Accel-Buffering'] = 'no'  # Disable nginx buffering

      begin
        agent.send_message(message, stream: true, **options) do |chunk|
          response.stream.write "data: #{chunk}\n\n"
        end
      rescue IOError
        # Client disconnected
      ensure
        response.stream.close
      end
    end

    # Archive a conversation
    def archive_conversation(conversation = current_conversation)
      conversation.archive!
    end
  end
end
