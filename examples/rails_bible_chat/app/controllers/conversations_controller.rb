class ConversationsController < ApplicationController
  include ActionController::Live

  # Show the main chat interface
  def index
    @conversations = ActiveIntelligence::Conversation.active.order(created_at: :desc).limit(10)
  end

  # Show a specific conversation
  def show
    @conversation = ActiveIntelligence::Conversation.find(params[:id])
    @messages = @conversation.messages.order(:created_at)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          conversation: {
            id: @conversation.id,
            agent_class: @conversation.agent_class,
            status: @conversation.status,
            created_at: @conversation.created_at
          },
          messages: @messages.map do |msg|
            {
              id: msg.id,
              role: msg.role,
              content: msg.content,
              tool_name: msg.tool_name,
              created_at: msg.created_at
            }
          end
        }
      end
    end
  end

  # Create a new conversation
  def create
    @conversation = ActiveIntelligence::Conversation.create!(
      agent_class: 'BibleStudyAgent',
      objective: params[:objective] || 'Bible study and exploration'
    )

    respond_to do |format|
      format.html { redirect_to conversation_path(@conversation) }
      format.json do
        render json: {
          id: @conversation.id,
          agent_class: @conversation.agent_class,
          created_at: @conversation.created_at
        }, status: :created
      end
    end
  end

  # Send a message (non-streaming)
  def send_message
    @conversation = ActiveIntelligence::Conversation.find(params[:id])
    agent = @conversation.agent

    message_content = params[:message]
    response = agent.send_message(message_content)

    render json: {
      response: response,
      message_count: @conversation.message_count
    }
  rescue StandardError => e
    Rails.logger.error "Error sending message: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: {
      error: "Failed to send message: #{e.message}"
    }, status: :unprocessable_entity
  end

  # Send a message (streaming)
  def send_message_streaming
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['Cache-Control'] = 'no-cache'

    @conversation = ActiveIntelligence::Conversation.find(params[:id])
    agent = @conversation.agent
    message_content = params[:message]

    begin
      agent.send_message(message_content, stream: true) do |chunk|
        response.stream.write "data: #{chunk}\n\n"
      end

      response.stream.write "data: [DONE]\n\n"
    rescue IOError
      # Client disconnected
      Rails.logger.info "Client disconnected from stream"
    rescue StandardError => e
      Rails.logger.error "Streaming error: #{e.message}\n#{e.backtrace.join("\n")}"
      response.stream.write "data: {\"error\": \"#{e.message}\"}\n\n"
    ensure
      response.stream.close
    end
  end
end
