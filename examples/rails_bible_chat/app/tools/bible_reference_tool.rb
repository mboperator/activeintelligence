require 'httparty'

class BibleReferenceTool < ActiveIntelligence::Tool
  name "bible_lookup"
  description "Look up Bible verses by reference (e.g., 'John 3:16', 'Genesis 1:1-3', 'Psalm 23')"

  param :reference,
        type: String,
        required: true,
        description: "The Bible reference to look up (e.g., 'John 3:16', 'Psalm 23:1-6', 'Matthew 5')"

  param :version,
        type: String,
        required: false,
        default: "KJV",
        enum: ["KJV", "ASV", "WEB"],
        description: "Bible translation version (KJV=King James, ASV=American Standard, WEB=World English Bible)"

  def execute(params)
    reference = params[:reference]
    version = params[:version] || "KJV"

    # Call Bible API
    result = fetch_bible_verse(reference, version)

    if result[:success]
      success_response({
        reference: reference,
        version: version,
        text: result[:text],
        verses: result[:verses]
      })
    else
      error_response(
        "Could not find Bible reference: #{reference}",
        details: { error: result[:error] }
      )
    end
  rescue StandardError => e
    error_response(
      "Failed to lookup Bible reference",
      details: { error: e.message, reference: params[:reference] }
    )
  end

  private

  def fetch_bible_verse(reference, version)
    # Using Bible API (https://bible-api.com)
    # This is a free, public API that doesn't require authentication
    url = "https://bible-api.com/#{URI.encode_www_form_component(reference)}"
    url += "?translation=#{version.downcase}" if version != "KJV"

    response = HTTParty.get(url, timeout: 10)

    if response.success?
      data = JSON.parse(response.body)

      # Format the verses
      verses = if data['verses'].is_a?(Array)
        data['verses'].map do |v|
          {
            book: v['book_name'],
            chapter: v['chapter'],
            verse: v['verse'],
            text: v['text']
          }
        end
      else
        []
      end

      {
        success: true,
        text: data['text'],
        reference: data['reference'],
        verses: verses
      }
    else
      {
        success: false,
        error: "API returned status #{response.code}"
      }
    end
  rescue JSON::ParserError => e
    {
      success: false,
      error: "Invalid API response: #{e.message}"
    }
  rescue HTTParty::Error, Net::ReadTimeout => e
    {
      success: false,
      error: "Network error: #{e.message}"
    }
  end
end
