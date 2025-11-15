class ShowEmojiTool < ActiveIntelligence::Tool
  execution_context :frontend

  name "show_emoji"
  description "Display an emoji or emoticon to the user in the chat interface. Use this to add visual emphasis or emotion to your responses."

  param :emoji,
        type: String,
        required: true,
        description: "The emoji to display (e.g., '🙏', '✝️', '📖', '❤️', '🕊️')"

  param :size,
        type: String,
        required: false,
        default: "large",
        enum: ["small", "medium", "large"],
        description: "The size to display the emoji"

  param :message,
        type: String,
        required: false,
        description: "Optional message to display alongside the emoji"

  def execute(params)
    # This tool runs on the frontend, so we just return the parameters
    # The React frontend will handle the actual display
    success_response({
      emoji: params[:emoji],
      size: params[:size] || "large",
      message: params[:message]
    })
  end
end
