# lib/scripture_quote_tool.rb
class ScriptureQuoteTool < ActiveIntelligence::QueryTool
  name "get_scripture_quote"
  description "Get an inspiring scripture quote related to a topic"

  param :topic, type: String, required: true,
        description: "Topic to find a related scripture quote for (e.g., 'love', 'faith', 'hope')"

  def execute(params)
    topic = params[:topic].to_s.downcase

    quotes = {
      "love" => "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life. - John 3:16",
      "faith" => "Now faith is confidence in what we hope for and assurance about what we do not see. - Hebrews 11:1",
      "hope" => "For I know the plans I have for you, declares the LORD, plans to prosper you and not to harm you, plans to give you hope and a future. - Jeremiah 29:11",
      "wisdom" => "The fear of the LORD is the beginning of wisdom, and knowledge of the Holy One is understanding. - Proverbs 9:10",
      "strength" => "I can do all this through him who gives me strength. - Philippians 4:13"
    }

    # Default quote if topic not found
    quote = quotes[topic] || "Trust in the LORD with all your heart and lean not on your own understanding. - Proverbs 3:5"

    success_response({
                       topic: topic,
                       quote: quote
                     })
  end
end
