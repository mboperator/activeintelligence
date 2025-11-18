require 'spec_helper'

RSpec.describe ActiveIntelligence::Agent, 'send_message' do
  # Define a test tool for testing
  let(:test_tool_class) do
    Class.new(ActiveIntelligence::Tool) do
      execution_context :backend
      name "test_tool"
      description "A test tool that returns data"

      param :query, type: String, required: true

      def execute(params)
        success_response({ result: "Tool executed with: #{params[:query]}" })
      end
    end
  end

  # Define test agent
  let(:test_agent_class) do
    tool_class = test_tool_class

    Class.new(ActiveIntelligence::Agent) do
      model :claude
      memory :in_memory
      identity "Test agent for send_message"

      tool tool_class
    end
  end

  let(:agent) do
    # Mock the setup_api_client before creating the agent
    agent_instance = test_agent_class.allocate
    allow(agent_instance).to receive(:setup_api_client)
    agent_instance.send(:initialize)
    agent_instance
  end

  describe '#send_message (non-streaming)' do
    context 'when Claude responds with text only (no tool calls)' do
      it 'returns the text response' do
        # Mock API to return a simple text response
        allow(agent).to receive(:call_api).and_return(
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Hello! How can I help you?",
            tool_calls: []
          )
        )

        response = agent.send_message("Hi there")

        expect(response).to eq("Hello! How can I help you?")
      end
    end

    context 'when Claude responds with a single tool call' do
      it 'executes the tool and returns only the final text response' do
        # First API call: Claude requests tool use
        tool_call_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "",  # Usually empty when using tools
          tool_calls: [
            {
              id: "toolu_123",
              name: "test_tool",
              parameters: { query: "hello" }
            }
          ]
        )

        # Second API call: Claude responds with final text after seeing tool result
        final_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "I used the tool and got: Tool executed with: hello",
          tool_calls: []
        )

        allow(agent).to receive(:call_api).and_return(tool_call_response, final_response)

        response = agent.send_message("Use the test tool")

        # Should ONLY contain the final text, NOT the tool result JSON
        expect(response).to eq("I used the tool and got: Tool executed with: hello")
        expect(response).not_to include('{"result"')
        expect(response).not_to include('"data"')
      end
    end

    context 'when Claude makes multiple tool calls in sequence' do
      it 'executes all tools and returns only the final text response' do
        # First API call: Claude requests tool use
        first_tool_call = ActiveIntelligence::Messages::AgentResponse.new(
          content: "",
          tool_calls: [
            {
              id: "toolu_123",
              name: "test_tool",
              parameters: { query: "first" }
            }
          ]
        )

        # Second API call: Claude requests another tool use
        second_tool_call = ActiveIntelligence::Messages::AgentResponse.new(
          content: "",
          tool_calls: [
            {
              id: "toolu_456",
              name: "test_tool",
              parameters: { query: "second" }
            }
          ]
        )

        # Third API call: Claude responds with final text
        final_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "I executed both tools successfully!",
          tool_calls: []
        )

        allow(agent).to receive(:call_api).and_return(
          first_tool_call,
          second_tool_call,
          final_response
        )

        response = agent.send_message("Use the tool twice")

        # Should ONLY contain the final text response
        expect(response).to eq("I executed both tools successfully!")
        expect(response).not_to include('{"result"')
        expect(response).not_to include('"data"')
      end
    end

    context 'when Claude makes multiple tool calls in parallel' do
      it 'executes all tools and returns only the final text response' do
        # First API call: Claude requests multiple tools at once
        parallel_tool_calls = ActiveIntelligence::Messages::AgentResponse.new(
          content: "",
          tool_calls: [
            {
              id: "toolu_123",
              name: "test_tool",
              parameters: { query: "first" }
            },
            {
              id: "toolu_456",
              name: "test_tool",
              parameters: { query: "second" }
            }
          ]
        )

        # Second API call: Claude responds with final text after seeing both results
        final_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "I executed both tools in parallel!",
          tool_calls: []
        )

        allow(agent).to receive(:call_api).and_return(
          parallel_tool_calls,
          final_response
        )

        response = agent.send_message("Use the tool twice in parallel")

        # Should ONLY contain the final text response
        expect(response).to eq("I executed both tools in parallel!")
        expect(response).not_to include('{"result"')
        expect(response).not_to include('"data"')
      end
    end

    context 'when process_tool_calls returns empty array (no tool calls)' do
      it 'returns the initial response content' do
        # Mock API to return a simple text response
        allow(agent).to receive(:call_api).and_return(
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Simple text response",
            tool_calls: []
          )
        )

        response = agent.send_message("Hello")

        expect(response).to eq("Simple text response")
      end
    end

    context 'message history management' do
      it 'adds messages in correct order' do
        # Mock API responses
        tool_call_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "",
          tool_calls: [
            {
              id: "toolu_123",
              name: "test_tool",
              parameters: { query: "test" }
            }
          ]
        )

        final_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "Done!",
          tool_calls: []
        )

        allow(agent).to receive(:call_api).and_return(tool_call_response, final_response)

        agent.send_message("Test")

        # Verify message order:
        # 1. UserMessage
        # 2. AgentResponse (with tool_calls)
        # 3. ToolResponse (completed)
        # 4. AgentResponse (final)
        messages = agent.messages

        expect(messages.size).to eq(4)
        expect(messages[0]).to be_a(ActiveIntelligence::Messages::UserMessage)
        expect(messages[1]).to be_a(ActiveIntelligence::Messages::AgentResponse)
        expect(messages[1].tool_calls).not_to be_empty
        expect(messages[2]).to be_a(ActiveIntelligence::Messages::ToolResponse)
        expect(messages[2].complete?).to be true
        expect(messages[3]).to be_a(ActiveIntelligence::Messages::AgentResponse)
        expect(messages[3].tool_calls).to be_empty
      end
    end

    context 'state management' do
      it 'sets state to completed after successful execution' do
        allow(agent).to receive(:call_api).and_return(
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Done",
            tool_calls: []
          )
        )

        agent.send_message("Test")

        expect(agent.state).to eq(ActiveIntelligence::Agent::STATES[:completed])
      end
    end
  end

  describe '#send_message (streaming)' do
    context 'when Claude responds with text only (no tool calls)' do
      it 'yields text chunks and does not return a string' do
        # Mock streaming API
        allow(agent).to receive(:call_streaming_api) do |&block|
          block.call("data: {\"type\":\"content_delta\",\"delta\":\"Hello\"}\n\n")
          block.call("data: {\"type\":\"content_delta\",\"delta\":\" there!\"}\n\n")

          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Hello there!",
            tool_calls: []
          )
        end

        chunks = []
        result = agent.send_message("Hi", stream: true) do |chunk|
          chunks << chunk
        end

        expect(chunks.size).to eq(2)
        expect(result).to be_nil  # Streaming doesn't return a string
      end
    end
  end
end
