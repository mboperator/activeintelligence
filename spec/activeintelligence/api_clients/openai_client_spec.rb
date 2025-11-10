# spec/activeintelligence/api_clients/openai_client_spec.rb
require 'spec_helper'
require 'webmock/rspec'
require 'json'

RSpec.describe ActiveIntelligence::ApiClients::OpenAIClient do
  let(:api_key) { 'test-api-key' }
  let(:client) { described_class.new(api_key: api_key) }

  before do
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
  end

  describe '#initialize' do
    it 'requires an API key' do
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
      allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('env-key')
      expect {
        described_class.new
      }.not_to raise_error
    end
  end

  describe '#format_messages' do
    context 'with system prompt' do
      it 'includes system prompt as first message' do
        messages = [
          ActiveIntelligence::Messages::UserMessage.new(content: "Hello")
        ]
        system_prompt = "You are a helpful assistant"

        result = client.send(:format_messages, messages, system_prompt)

        expect(result.first).to eq({ role: "system", content: "You are a helpful assistant" })
        expect(result.last).to eq({ role: "user", content: "Hello" })
      end

      it 'skips empty system prompt' do
        messages = [
          ActiveIntelligence::Messages::UserMessage.new(content: "Hello")
        ]

        result = client.send(:format_messages, messages, "")

        expect(result.length).to eq(1)
        expect(result.first[:role]).to eq("user")
      end
    end

    context 'with simple UserMessage' do
      it 'formats as simple message' do
        messages = [
          ActiveIntelligence::Messages::UserMessage.new(content: "Hello")
        ]

        result = client.send(:format_messages, messages, nil)

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

        result = client.send(:format_messages, messages, nil)

        expect(result).to eq([
          { role: "assistant", content: "Hi there!" }
        ])
      end
    end

    context 'with AgentResponse containing tool calls' do
      it 'formats with tool_calls array' do
        messages = [
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Let me search",
            tool_calls: [
              {
                id: "call_1",
                name: "search",
                parameters: { query: "test" }
              }
            ]
          )
        ]

        result = client.send(:format_messages, messages, nil)

        expect(result).to eq([
          {
            role: "assistant",
            content: "Let me search",
            tool_calls: [
              {
                id: "call_1",
                type: "function",
                function: {
                  name: "search",
                  arguments: '{"query":"test"}'  # JSON string
                }
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
              { id: "call_1", name: "search", parameters: { q: "a" } },
              { id: "call_2", name: "calculate", parameters: { expr: "2+2" } }
            ]
          )
        ]

        result = client.send(:format_messages, messages, nil)

        expect(result[0][:tool_calls].length).to eq(2)
        expect(result[0][:tool_calls][0][:type]).to eq("function")
        expect(result[0][:tool_calls][1][:type]).to eq("function")
      end
    end

    context 'with ToolResponse' do
      it 'formats as role "tool"' do
        messages = [
          ActiveIntelligence::Messages::ToolResponse.new(
            tool_name: "search",
            result: { data: "results" },
            tool_use_id: "call_1"
          )
        ]

        result = client.send(:format_messages, messages, nil)

        expect(result[0][:role]).to eq("tool")
        expect(result[0][:tool_call_id]).to eq("call_1")
        expect(result[0][:content]).to be_a(String)
      end
    end

    context 'with mixed message types' do
      it 'formats complex conversation' do
        messages = [
          ActiveIntelligence::Messages::UserMessage.new(content: "Hello"),
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Let me help",
            tool_calls: [
              { id: "call_1", name: "search", parameters: { q: "test" } }
            ]
          ),
          ActiveIntelligence::Messages::ToolResponse.new(
            tool_name: "search",
            result: { data: "found" },
            tool_use_id: "call_1"
          ),
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Here are results",
            tool_calls: []
          )
        ]

        result = client.send(:format_messages, messages, "You are helpful")

        expect(result.length).to eq(5)  # system + 4 messages
        expect(result[0][:role]).to eq("system")
        expect(result[1][:role]).to eq("user")
        expect(result[2][:role]).to eq("assistant")
        expect(result[3][:role]).to eq("tool")
        expect(result[4][:role]).to eq("assistant")
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
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_return(
            status: 200,
            body: {
              choices: [
                {
                  message: {
                    role: "assistant",
                    content: "Hello there!"
                  },
                  finish_reason: "stop"
                }
              ]
            }.to_json
          )

        result = client.call(messages, system_prompt)

        expect(result).to include(
          content: "Hello there!",
          tool_calls: [],
          stop_reason: "stop"
        )
      end

      it 'returns normalized response with tool calls' do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_return(
            status: 200,
            body: {
              choices: [
                {
                  message: {
                    role: "assistant",
                    content: "Let me search",
                    tool_calls: [
                      {
                        id: "call_1",
                        type: "function",
                        function: {
                          name: "search",
                          arguments: '{"query":"test"}'
                        }
                      }
                    ]
                  },
                  finish_reason: "tool_calls"
                }
              ]
            }.to_json
          )

        result = client.call(messages, system_prompt)

        expect(result[:content]).to eq("Let me search")
        expect(result[:tool_calls]).to eq([
          {
            id: "call_1",
            name: "search",
            parameters: { "query" => "test" }
          }
        ])
        expect(result[:stop_reason]).to eq("tool_calls")
      end

      it 'sends properly formatted request' do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .with { |request|
            body = JSON.parse(request.body)
            body["messages"][0]["role"] == "system" &&
            body["messages"][1]["role"] == "user" &&
            body["messages"][1]["content"] == "Hello"
          }
          .to_return(
            status: 200,
            body: {
              choices: [{ message: { content: "Hi" }, finish_reason: "stop" }]
            }.to_json
          )

        client.call(messages, system_prompt)
      end

      it 'includes tools in request when provided' do
        tools = [
          {
            name: "search",
            description: "Search for information",
            input_schema: { type: "object", properties: { query: { type: "string" } } }
          }
        ]

        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .with { |request|
            body = JSON.parse(request.body)
            body["tools"].is_a?(Array) &&
            body["tools"][0]["type"] == "function" &&
            body["tools"][0]["function"]["name"] == "search"
          }
          .to_return(
            status: 200,
            body: {
              choices: [{ message: { content: "Hi" }, finish_reason: "stop" }]
            }.to_json
          )

        client.call(messages, system_prompt, tools: tools)
      end
    end

    context 'with API errors' do
      it 'handles 400 errors' do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_return(status: 400, body: "Bad request")

        result = client.call(messages, system_prompt)

        expect(result).to include("400")
      end

      it 'handles 401 errors' do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_return(status: 401, body: "Unauthorized")

        result = client.call(messages, system_prompt)

        expect(result).to include("401")
      end
    end

    context 'with length truncation' do
      it 'warns on length finish_reason' do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_return(
            status: 200,
            body: {
              choices: [
                {
                  message: { content: "Truncated" },
                  finish_reason: "length"
                }
              ]
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
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\" there\"},\"finish_reason\":null}]}\n\n",
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n",
        "data: [DONE]\n\n"
      ].join

      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 200, body: streaming_response)

      chunks = []
      result = client.call_streaming(messages, system_prompt) do |chunk|
        chunks << chunk
      end

      expect(chunks).to eq(["Hello", " there"])
      expect(result[:content]).to eq("Hello there")
      expect(result[:stop_reason]).to eq("stop")
    end

    it 'handles tool calls in streaming' do
      streaming_response = [
        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"function\":{\"name\":\"search\",\"arguments\":\"\"}}]}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"query\\\":\\\"\"}}]}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"test\\\"}\"}}]}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n",
        "data: [DONE]\n\n"
      ].join

      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 200, body: streaming_response)

      result = client.call_streaming(messages, system_prompt) { }

      expect(result[:tool_calls].length).to eq(1)
      expect(result[:tool_calls][0][:name]).to eq("search")
      expect(result[:tool_calls][0][:parameters]).to eq({ "query" => "test" })
    end
  end
end
