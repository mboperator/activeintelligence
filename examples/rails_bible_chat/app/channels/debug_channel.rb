class DebugChannel < ApplicationCable::Channel
  def subscribed
    conversation = ActiveIntelligence::Conversation.find(params[:conversation_id])
    stream_for conversation
  end

  def unsubscribed
    # Cleanup when channel is closed
  end
end
