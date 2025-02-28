# lib/dad_joke_tool.rb
class ActiveIntelligence::DadJokeTool < ActiveIntelligence::QueryTool
  name "get_dad_joke"
  description "Get a random dad joke"
  
  param :category, type: String, required: false,
        description: "Optional category of joke (not actually used, just for demonstration)"

  def execute(params)
    jokes = [
      "Why don't scientists trust atoms? Because they make up everything!",
      "I told my wife she was drawing her eyebrows too high. She looked surprised.",
      "What do you call a fake noodle? An impasta.",
      "How do you organize a space party? You planet.",
      "Why did the scarecrow win an award? Because he was outstanding in his field.",
      "I'm reading a book about anti-gravity. It's impossible to put down.",
      "Did you hear about the mathematician who's afraid of negative numbers? He'll stop at nothing to avoid them.",
      "Why don't skeletons fight each other? They don't have the guts.",
      "What's the best thing about Switzerland? I don't know, but the flag is a big plus.",
      "I used to be a baker, but I couldn't make enough dough."
    ]

    # Select a random joke
    joke = jokes.sample

    success_response({
      joke: joke
    })
  end
end
