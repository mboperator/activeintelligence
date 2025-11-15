# spec/activeintelligence/api_clients/claude_client_spec.rb
require 'spec_helper'
require 'webmock/rspec'
require 'json'

RSpec.describe ActiveIntelligence::ApiClients::ClaudeClient do
  let(:api_key) { 'test-api-key' }
  let(:client) { described_class.new(api_key: api_key) }

  before do
    # Stub API requests by default
    stub_request(:post, "https://api.anthropic.com/v1/messages")
  end

  describe '#initialize' do
    it 'requires an API key' do
      # Stub ENV to return nil for ANTHROPIC_API_KEY
      allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return(nil)

      expect {
        described_class.new
      }.to raise_error(ActiveIntelligence::ConfigurationError, /API key is required/)
    end

    it 'accepts API key from options' do
      expect {
        described_class.new(api_key: 'test-key')
      }.not_to raise_error
    end

    it 'accepts API key from environment variable' do
      allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('env-key')
      expect {
        described_class.new
      }.not_to raise_error
    end
  end

  describe '#format_messages' do
    context 'with simple UserMessage' do
      it 'formats as simple text message' do
        messages = [
          ActiveIntelligence::Messages::UserMessage.new(content: "Hello")
        ]

        result = client.send(:format_messages, messages)

        expect(result).to eq([
          { role: "user", content: "Hello" }
        ])
      end
    end

    context 'with simple AgentResponse' do
      it 'formats text-only response' do
        messages = [
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Hi there!",
            tool_calls: []
          )
        ]

        result = client.send(:format_messages, messages)

        expect(result).to eq([
          { role: "assistant", content: "Hi there!" }
        ])
      end
    end

    context 'with AgentResponse containing tool calls' do
      it 'formats as content blocks with tool_use' do
        messages = [
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Let me search for that",
            tool_calls: [
              {
                id: "tool_1",
                name: "search",
                parameters: { query: "test" }
              }
            ]
          )
        ]

        result = client.send(:format_messages, messages)

        expect(result).to eq([
          {
            role: "assistant",
            content: [
              { type: "text", text: "Let me search for that" },
              {
                type: "tool_use",
                id: "tool_1",
                name: "search",
                input: { query: "test" }
              }
            ]
          }
        ])
      end

      it 'handles empty content with tool calls' do
        messages = [
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "",
            tool_calls: [
              {
                id: "tool_1",
                name: "search",
                parameters: { query: "test" }
              }
            ]
          )
        ]

        result = client.send(:format_messages, messages)

        expect(result).to eq([
          {
            role: "assistant",
            content: [
              {
                type: "tool_use",
                id: "tool_1",
                name: "search",
                input: { query: "test" }
              }
            ]
          }
        ])
      end

      it 'handles multiple tool calls' do
        messages = [
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Using multiple tools",
            tool_calls: [
              {
                id: "tool_1",
                name: "search",
                parameters: { query: "test" }
              },
              {
                id: "tool_2",
                name: "calculate",
                parameters: { expression: "2+2" }
              }
            ]
          )
        ]

        result = client.send(:format_messages, messages)

        expect(result[0][:content]).to include(
          { type: "text", text: "Using multiple tools" },
          {
            type: "tool_use",
            id: "tool_1",
            name: "search",
            input: { query: "test" }
          },
          {
            type: "tool_use",
            id: "tool_2",
            name: "calculate",
            input: { expression: "2+2" }
          }
        )
      end
    end

    context 'with single ToolResponse' do
      it 'formats as tool_result content block' do
        messages = [
          ActiveIntelligence::Messages::ToolResponse.new(
            tool_name: "search",
            result: { data: "results" },
            tool_use_id: "tool_1",
            status: ActiveIntelligence::Messages::ToolResponse::STATUSES[:complete]
          )
        ]

        result = client.send(:format_messages, messages)

        expect(result).to eq([
          {
            role: "user",
            content: [
              {
                type: "tool_result",
                tool_use_id: "tool_1",
                content: result[0][:content][0][:content],
                is_error: false
              }
            ]
          }
        ])
      end

      it 'includes error flag when tool fails' do
        messages = [
          ActiveIntelligence::Messages::ToolResponse.new(
            tool_name: "search",
            result: { error: true, message: "Failed" },
            tool_use_id: "tool_1",
            is_error: true,
            status: ActiveIntelligence::Messages::ToolResponse::STATUSES[:error]
          )
        ]

        result = client.send(:format_messages, messages)

        expect(result[0][:content][0][:is_error]).to be true
      end
    end

    context 'with consecutive ToolResponses' do
      it 'groups them into single message with multiple content blocks' do
        messages = [
          ActiveIntelligence::Messages::ToolResponse.new(
            tool_name: "search",
            result: { data: "result1" },
            tool_use_id: "tool_1",
            status: ActiveIntelligence::Messages::ToolResponse::STATUSES[:complete]
          ),
          ActiveIntelligence::Messages::ToolResponse.new(
            tool_name: "calculate",
            result: { data: "result2" },
            tool_use_id: "tool_2",
            status: ActiveIntelligence::Messages::ToolResponse::STATUSES[:complete]
          ),
          ActiveIntelligence::Messages::ToolResponse.new(
            tool_name: "fetch",
            result: { data: "result3" },
            tool_use_id: "tool_3",
            status: ActiveIntelligence::Messages::ToolResponse::STATUSES[:complete]
          )
        ]

        result = client.send(:format_messages, messages)

        # Should be grouped into single message
        expect(result.length).to eq(1)
        expect(result[0][:role]).to eq("user")
        expect(result[0][:content].length).to eq(3)

        expect(result[0][:content][0][:tool_use_id]).to eq("tool_1")
        expect(result[0][:content][1][:tool_use_id]).to eq("tool_2")
        expect(result[0][:content][2][:tool_use_id]).to eq("tool_3")
      end
    end

    context 'with mixed message types' do
      it 'formats complex conversation correctly' do
        messages = [
          ActiveIntelligence::Messages::UserMessage.new(content: "Hello"),
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Let me help",
            tool_calls: [
              { id: "tool_1", name: "search", parameters: { q: "test" } }
            ]
          ),
          ActiveIntelligence::Messages::ToolResponse.new(
            tool_name: "search",
            result: { data: "found" },
            tool_use_id: "tool_1",
            status: ActiveIntelligence::Messages::ToolResponse::STATUSES[:complete]
          ),
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Here are the results",
            tool_calls: []
          )
        ]

        result = client.send(:format_messages, messages)

        expect(result.length).to eq(4)
        expect(result[0]).to eq({ role: "user", content: "Hello" })
        expect(result[1][:role]).to eq("assistant")
        expect(result[1][:content]).to be_an(Array)
        expect(result[2][:role]).to eq("user")
        expect(result[2][:content]).to be_an(Array)
        expect(result[3]).to eq({ role: "assistant", content: "Here are the results" })
      end

      it 'separates non-consecutive ToolResponses' do
        messages = [
          ActiveIntelligence::Messages::ToolResponse.new(
            tool_name: "search",
            result: { data: "result1" },
            tool_use_id: "tool_1",
            status: ActiveIntelligence::Messages::ToolResponse::STATUSES[:complete]
          ),
          ActiveIntelligence::Messages::UserMessage.new(content: "Hello"),
          ActiveIntelligence::Messages::ToolResponse.new(
            tool_name: "calculate",
            result: { data: "result2" },
            tool_use_id: "tool_2",
            status: ActiveIntelligence::Messages::ToolResponse::STATUSES[:complete]
          )
        ]

        result = client.send(:format_messages, messages)

        # Should be 3 separate messages since ToolResponses aren't consecutive
        expect(result.length).to eq(3)
        expect(result[0][:content].length).to eq(1) # First ToolResponse alone
        expect(result[1][:role]).to eq("user")
        expect(result[1][:content]).to eq("Hello")
        expect(result[2][:content].length).to eq(1) # Second ToolResponse alone
      end
    end
  end

  describe '#call' do
    let(:messages) do
      [ActiveIntelligence::Messages::UserMessage.new(content: "Hello")]
    end
    let(:system_prompt) { "You are a helpful assistant" }

    context 'with successful response' do
      it 'returns normalized response with text content' do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(
            status: 200,
            body: {
              content: [
                { type: "text", text: "Hello there!" }
              ],
              stop_reason: "end_turn"
            }.to_json
          )

        result = client.call(messages, system_prompt)

        expect(result).to include(
          content: "Hello there!",
          tool_calls: [],
          stop_reason: "end_turn"
        )
      end

      it 'returns normalized response with tool calls' do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(
            status: 200,
            body: {
              content: [
                { type: "text", text: "Let me search" },
                {
                  type: "tool_use",
                  id: "tool_1",
                  name: "search",
                  input: { query: "test" }
                }
              ],
              stop_reason: "tool_use"
            }.to_json
          )

        result = client.call(messages, system_prompt)

        expect(result[:content]).to eq("Let me search")
        expect(result[:tool_calls]).to eq([
          {
            id: "tool_1",
            name: "search",
            parameters: { "query" => "test" }
          }
        ])
        expect(result[:stop_reason]).to eq("tool_use")
      end

      it 'sends properly formatted request' do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .with { |request|
            body = JSON.parse(request.body)
            body["messages"] == [{ "role" => "user", "content" => "Hello" }]
          }
          .to_return(
            status: 200,
            body: { content: [{ type: "text", text: "Hi" }], stop_reason: "end_turn" }.to_json
          )

        client.call(messages, system_prompt)
      end

      it 'includes tools in request when provided' do
        tools = [
          {
            name: "search",
            description: "Search for information",
            input_schema: { type: "object", properties: {} }
          }
        ]

        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .with { |request|
            body = JSON.parse(request.body)
            body["tools"].is_a?(Array) && body["tools"].length == 1
          }
          .to_return(
            status: 200,
            body: { content: [{ type: "text", text: "Hi" }], stop_reason: "end_turn" }.to_json
          )

        client.call(messages, system_prompt, tools: tools)
      end

      it 'enables prompt caching by default' do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .with { |request|
            body = JSON.parse(request.body)
            body["system"].is_a?(Array) &&
            body["system"][0]["cache_control"] == { "type" => "ephemeral" }
          }
          .to_return(
            status: 200,
            body: { content: [{ type: "text", text: "Hi" }], stop_reason: "end_turn" }.to_json
          )

        client.call(messages, system_prompt)
      end

      it 'can disable prompt caching' do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .with { |request|
            body = JSON.parse(request.body)
            body["system"].is_a?(String)
          }
          .to_return(
            status: 200,
            body: { content: [{ type: "text", text: "Hi" }], stop_reason: "end_turn" }.to_json
          )

        client.call(messages, system_prompt, enable_prompt_caching: false)
      end
    end

    context 'with API errors' do
      it 'handles 400 errors' do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(status: 400, body: "Bad request")

        result = client.call(messages, system_prompt)

        expect(result).to include("400")
      end

      it 'handles 401 errors' do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(status: 401, body: "Unauthorized")

        result = client.call(messages, system_prompt)

        expect(result).to include("401")
      end

      it 'handles network errors' do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_raise(StandardError.new("Network error"))

        result = client.call(messages, system_prompt)

        expect(result).to include("Network error")
      end
    end

    context 'with special response types' do
      it 'handles responses with thinking blocks' do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(
            status: 200,
            body: {
              content: [
                { type: "thinking", thinking: "Let me think..." },
                { type: "text", text: "Here's my answer" }
              ],
              stop_reason: "end_turn"
            }.to_json
          )

        result = client.call(messages, system_prompt)

        expect(result[:content]).to eq("Here's my answer")
      end

      it 'handles empty content with only tool calls' do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(
            status: 200,
            body: {
              content: [
                {
                  type: "tool_use",
                  id: "tool_1",
                  name: "search",
                  input: { query: "test" }
                }
              ],
              stop_reason: "tool_use"
            }.to_json
          )

        result = client.call(messages, system_prompt)

        expect(result[:content]).to eq("")
        expect(result[:tool_calls].length).to eq(1)
      end

      it 'warns on max_tokens truncation' do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(
            status: 200,
            body: {
              content: [{ type: "text", text: "Truncated" }],
              stop_reason: "max_tokens"
            }.to_json
          )

        logger = instance_double("Logger")
        allow(ActiveIntelligence::Config).to receive(:logger).and_return(logger)
        expect(logger).to receive(:warn).with(/max_tokens/)

        client.call(messages, system_prompt)
      end
    end
  end

  describe '#call_streaming' do
    let(:messages) do
      [ActiveIntelligence::Messages::UserMessage.new(content: "Hello")]
    end
    let(:system_prompt) { "You are a helpful assistant" }

    it 'yields text chunks as they arrive' do
      streaming_response = [
        "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n",
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" there\"}}\n\n",
        "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n"
      ].join

      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 200, body: streaming_response)

      chunks = []
      result = client.call_streaming(messages, system_prompt) do |chunk|
        chunks << chunk
      end

      # Chunks should be SSE-formatted
      expect(chunks).to eq(["data: Hello\n\n", "data:  there\n\n"])
      expect(result[:content]).to eq("Hello there")
      expect(result[:stop_reason]).to eq("end_turn")
    end

    it 'handles tool calls in streaming' do
      streaming_response = [
        "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tool_1\",\"name\":\"search\"}}\n\n",
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"query\\\":\"}}\n\n",
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"\\\"test\\\"}\"}}\n\n",
        "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}\n\n"
      ].join

      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 200, body: streaming_response)

      result = client.call_streaming(messages, system_prompt) { }

      expect(result[:tool_calls]).to eq([
        {
          id: "tool_1",
          name: "search",
          parameters: { "query" => "test" }
        }
      ])
    end

    it 'handles mixed text and tool calls' do
      streaming_response = [
        "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Let me search\"}}\n\n",
        "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tool_1\",\"name\":\"search\"}}\n\n",
        "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"q\\\":\\\"test\\\"}\"}}\n\n",
        "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}\n\n"
      ].join

      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 200, body: streaming_response)

      chunks = []
      result = client.call_streaming(messages, system_prompt) { |chunk| chunks << chunk }

      # Chunks should be SSE-formatted
      expect(chunks).to eq(["data: Let me search\n\n"])
      expect(result[:content]).to eq("Let me search")
      expect(result[:tool_calls].length).to eq(1)
    end

    it 'handles thinking blocks without yielding them' do
      streaming_response = [
        "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"thinking\",\"thinking\":\"\"}}\n\n",
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"Hmm...\"}}\n\n",
        "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
        "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"text_delta\",\"text\":\"Answer\"}}\n\n",
        "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n"
      ].join

      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 200, body: streaming_response)

      chunks = []
      result = client.call_streaming(messages, system_prompt) { |chunk| chunks << chunk }

      # Should not yield thinking content to user, chunks should be SSE-formatted
      expect(chunks).to eq(["data: Answer\n\n"])
      expect(result[:content]).to eq("Answer")
    end

    it 'handles errors during streaming' do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 500, body: "Server error")

      result = client.call_streaming(messages, system_prompt) { }

      expect(result).to include("500")
    end
  end
end
