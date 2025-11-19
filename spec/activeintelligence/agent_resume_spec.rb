require 'spec_helper'

RSpec.describe ActiveIntelligence::Agent, 'resume_with_completed_tools' do
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
      identity "Test agent for resume"

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

  describe '#resume_with_completed_tools (non-streaming)' do
    context 'when there are completed tool results to send' do
      it 'sends the tool results to Claude and returns the final response' do
        # Simulate a scenario where tools were executed but results weren't sent to Claude
        # Message history: UserMessage -> AgentResponse (with tool_calls) -> ToolResponse (complete)

        user_message = ActiveIntelligence::Messages::UserMessage.new(content: "Use the tool")
        agent_response_with_tools = ActiveIntelligence::Messages::AgentResponse.new(
          content: "",
          tool_calls: [
            {
              id: "toolu_123",
              name: "test_tool",
              parameters: { query: "hello" }
            }
          ]
        )
        tool_response = ActiveIntelligence::Messages::ToolResponse.new(
          tool_name: "test_tool",
          tool_use_id: "toolu_123",
          parameters: { query: "hello" },
          status: :complete
        )
        tool_response.complete!({ success: true, data: { result: "Tool executed with: hello" } })

        # Manually build message history to simulate the crash scenario
        agent.instance_variable_set(:@messages, [
          user_message,
          agent_response_with_tools,
          tool_response
        ])

        # Mock the API call that will happen when resuming
        final_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "I used the tool and got: Tool executed with: hello",
          tool_calls: []
        )
        allow(agent).to receive(:call_api).and_return(final_response)

        # Resume the conversation
        response = agent.resume_with_completed_tools

        expect(response).to eq("I used the tool and got: Tool executed with: hello")
        expect(agent.state).to eq(ActiveIntelligence::Agent::STATES[:completed])
      end

      it 'handles multiple completed tool results' do
        # Simulate multiple tool calls that were all completed
        user_message = ActiveIntelligence::Messages::UserMessage.new(content: "Use tools")
        agent_response_with_tools = ActiveIntelligence::Messages::AgentResponse.new(
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

        tool_response_1 = ActiveIntelligence::Messages::ToolResponse.new(
          tool_name: "test_tool",
          tool_use_id: "toolu_123",
          parameters: { query: "first" },
          status: :complete
        )
        tool_response_1.complete!({ success: true, data: { result: "First result" } })

        tool_response_2 = ActiveIntelligence::Messages::ToolResponse.new(
          tool_name: "test_tool",
          tool_use_id: "toolu_456",
          parameters: { query: "second" },
          status: :complete
        )
        tool_response_2.complete!({ success: true, data: { result: "Second result" } })

        agent.instance_variable_set(:@messages, [
          user_message,
          agent_response_with_tools,
          tool_response_1,
          tool_response_2
        ])

        final_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "Both tools executed successfully",
          tool_calls: []
        )
        allow(agent).to receive(:call_api).and_return(final_response)

        response = agent.resume_with_completed_tools

        expect(response).to eq("Both tools executed successfully")
        expect(agent.state).to eq(ActiveIntelligence::Agent::STATES[:completed])
      end

      it 'continues processing if Claude requests more tool calls' do
        # Setup: completed tool result exists
        user_message = ActiveIntelligence::Messages::UserMessage.new(content: "Use tool")
        agent_response_with_tools = ActiveIntelligence::Messages::AgentResponse.new(
          content: "",
          tool_calls: [
            {
              id: "toolu_123",
              name: "test_tool",
              parameters: { query: "first" }
            }
          ]
        )
        tool_response = ActiveIntelligence::Messages::ToolResponse.new(
          tool_name: "test_tool",
          tool_use_id: "toolu_123",
          parameters: { query: "first" },
          status: :complete
        )
        tool_response.complete!({ success: true, data: { result: "First result" } })

        agent.instance_variable_set(:@messages, [
          user_message,
          agent_response_with_tools,
          tool_response
        ])

        # First resume call: Claude requests another tool
        second_tool_call_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "",
          tool_calls: [
            {
              id: "toolu_456",
              name: "test_tool",
              parameters: { query: "second" }
            }
          ]
        )

        # Second call: Claude provides final response
        final_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "All done!",
          tool_calls: []
        )

        allow(agent).to receive(:call_api).and_return(
          second_tool_call_response,
          final_response
        )

        response = agent.resume_with_completed_tools

        expect(response).to eq("All done!")
        expect(agent.state).to eq(ActiveIntelligence::Agent::STATES[:completed])
      end

      it 'resets state from awaiting_tool_results to idle before resuming' do
        # Simulate state stuck in awaiting_tool_results
        user_message = ActiveIntelligence::Messages::UserMessage.new(content: "Use tool")
        agent_response_with_tools = ActiveIntelligence::Messages::AgentResponse.new(
          content: "",
          tool_calls: [
            {
              id: "toolu_123",
              name: "test_tool",
              parameters: { query: "test" }
            }
          ]
        )
        tool_response = ActiveIntelligence::Messages::ToolResponse.new(
          tool_name: "test_tool",
          tool_use_id: "toolu_123",
          parameters: { query: "test" },
          status: :complete
        )
        tool_response.complete!({ success: true, data: { result: "Done" } })

        agent.instance_variable_set(:@messages, [
          user_message,
          agent_response_with_tools,
          tool_response
        ])
        agent.instance_variable_set(:@state, ActiveIntelligence::Agent::STATES[:awaiting_tool_results])

        final_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "Resumed successfully",
          tool_calls: []
        )
        allow(agent).to receive(:call_api).and_return(final_response)

        # State should be awaiting_tool_results before resume
        expect(agent.state).to eq(ActiveIntelligence::Agent::STATES[:awaiting_tool_results])

        response = agent.resume_with_completed_tools

        # State should be completed after resume
        expect(agent.state).to eq(ActiveIntelligence::Agent::STATES[:completed])
        expect(response).to eq("Resumed successfully")
      end
    end

    context 'when there are no completed tool results' do
      it 'raises an error if conversation is empty' do
        # Empty conversation
        agent.instance_variable_set(:@messages, [])

        expect {
          agent.resume_with_completed_tools
        }.to raise_error(ActiveIntelligence::Error, /no completed tool results found/)
      end

      it 'raises an error if last message is not a tool response' do
        # Last message is a regular agent response
        user_message = ActiveIntelligence::Messages::UserMessage.new(content: "Hello")
        agent_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "Hi there!",
          tool_calls: []
        )

        agent.instance_variable_set(:@messages, [user_message, agent_response])

        expect {
          agent.resume_with_completed_tools
        }.to raise_error(ActiveIntelligence::Error, /no completed tool results found/)
      end

      it 'raises an error if last tool response is pending' do
        # Tool response is pending, not complete
        user_message = ActiveIntelligence::Messages::UserMessage.new(content: "Use tool")
        agent_response_with_tools = ActiveIntelligence::Messages::AgentResponse.new(
          content: "",
          tool_calls: [
            {
              id: "toolu_123",
              name: "test_tool",
              parameters: { query: "test" }
            }
          ]
        )
        tool_response = ActiveIntelligence::Messages::ToolResponse.new(
          tool_name: "test_tool",
          tool_use_id: "toolu_123",
          parameters: { query: "test" },
          status: :pending  # Still pending
        )

        agent.instance_variable_set(:@messages, [
          user_message,
          agent_response_with_tools,
          tool_response
        ])

        expect {
          agent.resume_with_completed_tools
        }.to raise_error(ActiveIntelligence::Error, /no completed tool results found/)
      end
    end
  end

  describe '#resume_with_completed_tools (streaming)' do
    context 'when there are completed tool results to send' do
      it 'streams the response from Claude' do
        # Setup completed tool result
        user_message = ActiveIntelligence::Messages::UserMessage.new(content: "Use tool")
        agent_response_with_tools = ActiveIntelligence::Messages::AgentResponse.new(
          content: "",
          tool_calls: [
            {
              id: "toolu_123",
              name: "test_tool",
              parameters: { query: "test" }
            }
          ]
        )
        tool_response = ActiveIntelligence::Messages::ToolResponse.new(
          tool_name: "test_tool",
          tool_use_id: "toolu_123",
          parameters: { query: "test" },
          status: :complete
        )
        tool_response.complete!({ success: true, data: { result: "Done" } })

        agent.instance_variable_set(:@messages, [
          user_message,
          agent_response_with_tools,
          tool_response
        ])

        # Mock streaming API
        allow(agent).to receive(:call_streaming_api) do |&block|
          block.call("data: {\"type\":\"content_delta\",\"delta\":\"Resume\"}\n\n")
          block.call("data: {\"type\":\"content_delta\",\"delta\":\" successful!\"}\n\n")

          ActiveIntelligence::Messages::AgentResponse.new(
            content: "Resume successful!",
            tool_calls: []
          )
        end

        chunks = []
        agent.resume_with_completed_tools(stream: true) do |chunk|
          chunks << chunk
        end

        expect(chunks.size).to eq(2)
        expect(chunks[0]).to include("Resume")
        expect(chunks[1]).to include(" successful!")
      end
    end
  end

  describe '#has_completed_tools_to_send? (private method)' do
    it 'returns true when last message is a completed tool response' do
      tool_response = ActiveIntelligence::Messages::ToolResponse.new(
        tool_name: "test_tool",
        tool_use_id: "toolu_123",
        parameters: { query: "test" },
        status: :complete
      )
      tool_response.complete!({ success: true })

      agent.instance_variable_set(:@messages, [tool_response])

      expect(agent.send(:has_completed_tools_to_send?)).to be true
    end

    it 'returns false when last message is not a tool response' do
      agent_response = ActiveIntelligence::Messages::AgentResponse.new(
        content: "Hello",
        tool_calls: []
      )

      agent.instance_variable_set(:@messages, [agent_response])

      expect(agent.send(:has_completed_tools_to_send?)).to be false
    end

    it 'returns false when last tool response is pending' do
      tool_response = ActiveIntelligence::Messages::ToolResponse.new(
        tool_name: "test_tool",
        tool_use_id: "toolu_123",
        parameters: { query: "test" },
        status: :pending
      )

      agent.instance_variable_set(:@messages, [tool_response])

      expect(agent.send(:has_completed_tools_to_send?)).to be false
    end

    it 'returns true when there are multiple consecutive completed tool responses' do
      tool_response_1 = ActiveIntelligence::Messages::ToolResponse.new(
        tool_name: "test_tool",
        tool_use_id: "toolu_123",
        parameters: { query: "first" },
        status: :complete
      )
      tool_response_1.complete!({ success: true })

      tool_response_2 = ActiveIntelligence::Messages::ToolResponse.new(
        tool_name: "test_tool",
        tool_use_id: "toolu_456",
        parameters: { query: "second" },
        status: :complete
      )
      tool_response_2.complete!({ success: true })

      agent.instance_variable_set(:@messages, [tool_response_1, tool_response_2])

      expect(agent.send(:has_completed_tools_to_send?)).to be true
    end

    it 'returns false when messages array is empty' do
      agent.instance_variable_set(:@messages, [])

      expect(agent.send(:has_completed_tools_to_send?)).to be false
    end
  end
end
