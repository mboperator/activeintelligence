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

    # Check if we're resuming from frontend tool execution
    if params[:tool_results].present?
      response = agent.continue_with_tool_results(params[:tool_results])
    else
      message_content = params[:message]
      response = agent.send_message(message_content)
    end

    # Handle different response types
    if response.is_a?(Hash) && response[:status] == :awaiting_frontend_tool
      render json: {
        type: 'frontend_tool_request',
        tools: response[:tools],
        conversation_id: response[:conversation_id],
        message_count: @conversation.message_count
      }
    else
      render json: {
        type: 'completed',
        response: response,
        message_count: @conversation.message_count
      }
    end
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

    begin
      # Check if we're resuming from frontend tool execution
      if params[:tool_results].present?
        agent.continue_with_tool_results(params[:tool_results], stream: true) do |chunk|
          response.stream.write chunk
        end
      else
        message_content = params[:message]
        agent.send_message(message_content, stream: true) do |chunk|
          response.stream.write chunk
        end
      end

      # Note: [DONE] is sent by process_tool_calls_streaming if frontend tool is needed
      # Otherwise, we send it here
      unless agent.paused_for_frontend?
        response.stream.write "data: [DONE]\n\n"
      end
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
