require 'spec_helper'

RSpec.describe ActiveIntelligence::Agent, 'hybrid tools' do
  # Define test tools
  let(:backend_tool_class) do
    Class.new(ActiveIntelligence::Tool) do
      execution_context :backend
      name "backend_tool"
      description "A backend tool"

      def execute(params)
        success_response({ result: "backend executed" })
      end
    end
  end

  let(:frontend_tool_class) do
    Class.new(ActiveIntelligence::Tool) do
      execution_context :frontend
      name "frontend_tool"
      description "A frontend tool"

      param :action, type: String, required: true

      def execute(params)
        success_response({ action: params[:action] })
      end
    end
  end

  # Define test agent
  let(:test_agent_class) do
    backend = backend_tool_class
    frontend = frontend_tool_class

    Class.new(ActiveIntelligence::Agent) do
      model :claude
      memory :in_memory
      identity "Test agent"

      tool backend
      tool frontend
    end
  end

  before do
    # Stub API client initialization to avoid requiring API key
    allow_any_instance_of(test_agent_class).to receive(:setup_api_client)
  end

  let(:agent) { test_agent_class.new }

  describe 'initialization' do
    it 'sets initial state to idle' do
      expect(agent.state).to eq(ActiveIntelligence::Agent::STATES[:idle])
    end

    it 'includes both frontend and backend tools' do
      expect(agent.tools.size).to eq(2)
    end
  end

  describe '#partition_tool_calls' do
    let(:mixed_tool_calls) do
      [
        { id: "1", name: "backend_tool", parameters: {} },
        { id: "2", name: "frontend_tool", parameters: { action: "test" } },
        { id: "3", name: "backend_tool", parameters: {} }
      ]
    end

    it 'separates frontend and backend tools' do
      frontend_tools, backend_tools = agent.send(:partition_tool_calls, mixed_tool_calls)

      expect(frontend_tools.size).to eq(1)
      expect(backend_tools.size).to eq(2)

      expect(frontend_tools.first[:name]).to eq("frontend_tool")
      expect(backend_tools.map { |t| t[:name] }).to all(eq("backend_tool"))
    end

    context 'with only backend tools' do
      let(:backend_only_calls) do
        [
          { id: "1", name: "backend_tool", parameters: {} },
          { id: "2", name: "backend_tool", parameters: {} }
        ]
      end

      it 'returns empty frontend array' do
        frontend_tools, backend_tools = agent.send(:partition_tool_calls, backend_only_calls)

        expect(frontend_tools).to be_empty
        expect(backend_tools.size).to eq(2)
      end
    end

    context 'with only frontend tools' do
      let(:frontend_only_calls) do
        [
          { id: "1", name: "frontend_tool", parameters: { action: "test1" } },
          { id: "2", name: "frontend_tool", parameters: { action: "test2" } }
        ]
      end

      it 'returns empty backend array' do
        frontend_tools, backend_tools = agent.send(:partition_tool_calls, frontend_only_calls)

        expect(frontend_tools.size).to eq(2)
        expect(backend_tools).to be_empty
      end
    end
  end

  describe '#find_tool' do
    it 'finds backend tool by name' do
      tool = agent.send(:find_tool, "backend_tool")
      expect(tool).not_to be_nil
      expect(tool.class.name).to eq("backend_tool")
    end

    it 'finds frontend tool by name' do
      tool = agent.send(:find_tool, "frontend_tool")
      expect(tool).not_to be_nil
      expect(tool.class.name).to eq("frontend_tool")
    end

    it 'returns nil for unknown tool' do
      tool = agent.send(:find_tool, "unknown_tool")
      expect(tool).to be_nil
    end
  end

  describe 'state management' do
    describe '#paused_for_frontend?' do
      it 'returns false when idle' do
        expect(agent.send(:paused_for_frontend?)).to be false
      end

      it 'returns true when awaiting tool results' do
        agent.instance_variable_set(:@state, ActiveIntelligence::Agent::STATES[:awaiting_tool_results])
        expect(agent.send(:paused_for_frontend?)).to be true
      end

      it 'returns false when completed' do
        agent.instance_variable_set(:@state, ActiveIntelligence::Agent::STATES[:completed])
        expect(agent.send(:paused_for_frontend?)).to be false
      end
    end
  end

  describe '#continue_with_tool_results' do
    let(:tool_results) do
      [
        {
          tool_use_id: "toolu_123",
          result: { success: true, data: { action: "completed" } }
        }
      ]
    end

    context 'when agent is not paused' do
      it 'raises an error' do
        expect {
          agent.continue_with_tool_results(tool_results)
        }.to raise_error(ActiveIntelligence::Error, /Cannot continue.*idle/)
      end
    end

    context 'when agent is paused' do
      before do
        agent.instance_variable_set(:@state, ActiveIntelligence::Agent::STATES[:awaiting_tool_results])

        # Add a mock message to prevent empty message array issues
        agent.instance_variable_get(:@messages) <<
          ActiveIntelligence::Messages::AgentResponse.new(
            content: "",
            tool_calls: []  # Empty tool_calls so process_tool_calls doesn't loop
          )

        # Add a pending tool response that matches the tool_results
        agent.instance_variable_get(:@messages) <<
          ActiveIntelligence::Messages::ToolResponse.new(
            tool_name: "frontend_tool",
            tool_use_id: "toolu_123",
            parameters: { action: "test" },
            status: ActiveIntelligence::Messages::ToolResponse::STATUSES[:pending]
          )
      end

      it 'marks pending tool responses as complete' do
        # Mock API calls to avoid needing actual API
        mock_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "All tools completed",
          tool_calls: []
        )
        allow(agent).to receive(:call_api).and_return(mock_response)
        allow(agent).to receive(:process_tool_calls).and_return([])

        agent.continue_with_tool_results(tool_results)

        tool_response = agent.messages.find { |m| m.is_a?(ActiveIntelligence::Messages::ToolResponse) && m.tool_use_id == "toolu_123" }
        expect(tool_response).not_to be_nil
        expect(tool_response.complete?).to be true
      end

      it 'updates state from awaiting_tool_results to idle during processing' do
        # Mock API calls
        mock_response = ActiveIntelligence::Messages::AgentResponse.new(
          content: "All tools completed",
          tool_calls: []
        )
        allow(agent).to receive(:call_api) do
          # State should be idle when calling API
          expect(agent.state).to eq(ActiveIntelligence::Agent::STATES[:idle])
          mock_response
        end
        allow(agent).to receive(:process_tool_calls).and_return([])

        agent.continue_with_tool_results(tool_results)
      end
    end
  end

  describe 'tool execution' do
    describe '#execute_tool_call' do
      it 'executes backend tool' do
        result = agent.send(:execute_tool_call, "backend_tool", {})

        expect(result).to be_a(Hash)
        expect(result[:success]).to be true
        expect(result[:data][:result]).to eq("backend executed")
      end

      it 'executes frontend tool' do
        result = agent.send(:execute_tool_call, "frontend_tool", { action: "test" })

        expect(result).to be_a(Hash)
        expect(result[:success]).to be true
        expect(result[:data][:action]).to eq("test")
      end

      it 'returns error message for unknown tool' do
        result = agent.send(:execute_tool_call, "unknown_tool", {})

        expect(result).to be_a(String)
        expect(result).to include("Tool not found")
      end
    end
  end

  describe '#build_pending_tools_response' do
    before do
      # For in-memory agent without conversation
      agent.instance_variable_set(:@conversation, nil)

      # Add pending tool responses to messages
      agent.instance_variable_get(:@messages) <<
        ActiveIntelligence::Messages::ToolResponse.new(
          tool_name: "frontend_tool",
          tool_use_id: "toolu_123",
          parameters: { action: "test" },
          status: ActiveIntelligence::Messages::ToolResponse::STATUSES[:pending]
        )
    end

    it 'builds response hash with correct structure' do
      response = agent.send(:build_pending_tools_response)

      expect(response).to be_a(Hash)
      expect(response[:status]).to eq(:awaiting_tool_results)
      expect(response[:pending_tools]).to be_an(Array)
      expect(response[:pending_tools].size).to eq(1)

      pending_tool = response[:pending_tools].first
      expect(pending_tool[:tool_use_id]).to eq("toolu_123")
      expect(pending_tool[:tool_name]).to eq("frontend_tool")
      expect(pending_tool[:tool_input]).to eq({ action: "test" })
    end

    it 'includes only pending tool responses' do
      # Add a completed tool response
      agent.instance_variable_get(:@messages) <<
        ActiveIntelligence::Messages::ToolResponse.new(
          tool_name: "backend_tool",
          tool_use_id: "toolu_456",
          parameters: {},
          result: { success: true, data: {} },
          status: ActiveIntelligence::Messages::ToolResponse::STATUSES[:complete]
        )

      response = agent.send(:build_pending_tools_response)

      # Should only include the pending tool
      expect(response[:pending_tools].size).to eq(1)
      expect(response[:pending_tools].first[:tool_use_id]).to eq("toolu_123")
    end
  end
end
