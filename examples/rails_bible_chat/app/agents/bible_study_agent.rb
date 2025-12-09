class BibleStudyAgent < ActiveIntelligence::Agent
  model :claude
  memory :active_record

  identity <<~IDENTITY
    You are a knowledgeable and friendly Bible study assistant. Your role is to help users
    explore and understand the Bible through conversation.

    When users ask about specific Bible verses or passages:
    - Use the bible_lookup tool to retrieve the actual text
    - Provide context about the passage (who wrote it, when, why)
    - Explain the meaning in clear, accessible language
    - Connect it to broader biblical themes when relevant

    When users ask general questions about the Bible:
    - Share your knowledge about biblical history, context, and interpretation
    - Be respectful of different theological perspectives
    - Encourage users to read the actual text using the lookup tool

    Guidelines:
    - Be warm and encouraging in your tone
    - Use the bible_lookup tool whenever specific verses are mentioned
    - Use the show_emoji tool to add visual emphasis (e.g., 🙏 for prayer, ✝️ for Christ, 📖 for scripture)
    - Explain concepts clearly without being condescending
    - If you're unsure, say so and suggest looking up the relevant passage
    - Help users understand both the literal meaning and spiritual significance
  IDENTITY

  tool BibleReferenceTool
  tool ShowEmojiTool

  # Observability hooks - broadcast all events to debug panel
  on_session_start { |session| broadcast_hook('on_session_start', session.to_h) }
  on_session_end { |session| broadcast_hook('on_session_end', session.to_h) }
  on_turn_start { |turn| broadcast_hook('on_turn_start', turn.to_h) }
  on_turn_end { |turn| broadcast_hook('on_turn_end', turn.to_h) }
  on_response_start { |response| broadcast_hook('on_response_start', response.to_h) }
  on_response_end { |response| broadcast_hook('on_response_end', response.to_h) }
  on_response_chunk { |chunk| broadcast_hook('on_response_chunk', chunk.to_h) }
  on_thinking_start { |thinking| broadcast_hook('on_thinking_start', thinking.to_h) }
  on_thinking_end { |thinking| broadcast_hook('on_thinking_end', thinking.to_h) }
  on_tool_start { |tool| broadcast_hook('on_tool_start', tool.to_h) }
  on_tool_end { |tool| broadcast_hook('on_tool_end', tool.to_h) }
  on_tool_error { |tool| broadcast_hook('on_tool_error', tool.to_h) }
  on_message_added { |message| broadcast_hook('on_message_added', { type: message.class.name, content_preview: message.content&.to_s&.slice(0, 100) }) }
  on_iteration { |iteration| broadcast_hook('on_iteration', iteration.to_h) }
  on_error { |error_ctx| broadcast_hook('on_error', error_ctx.to_h) }
  on_stop { |stop| broadcast_hook('on_stop', stop.to_h) }

  private

  def broadcast_hook(hook_name, payload)
    return unless @conversation

    DebugChannel.broadcast_to(
      @conversation,
      {
        hook: hook_name,
        payload: payload,
        timestamp: Time.now.iso8601
      }
    )
  rescue => e
    # Don't let broadcasting errors break the agent
    Rails.logger.error "Failed to broadcast hook #{hook_name}: #{e.message}"
  end
end
