require 'spec_helper'

RSpec.describe ActiveIntelligence::Agent, 'context' do
  # Define a tool that requires context
  let(:scoped_tool_class) do
    Class.new(ActiveIntelligence::Tool) do
      name "find_events"
      description "Find events scoped to current school"

      context_field :current_user, required: true
      context_field :current_school, required: true

      param :query, type: String, required: false

      def execute(params)
        success_response({
          events: ["Event 1", "Event 2"],
          school_id: current_school.id,
          user_id: current_user.id,
          query: params[:query]
        })
      end
    end
  end

  # Define a simple tool without context requirements
  let(:simple_tool_class) do
    Class.new(ActiveIntelligence::Tool) do
      name "get_time"
      description "Get current time"

      def execute(params)
        success_response({ time: "2024-01-01 12:00:00" })
      end
    end
  end

  describe 'context initialization' do
    let(:agent_class) do
      tool = scoped_tool_class

      Class.new(ActiveIntelligence::Agent) do
        model :claude
        memory :in_memory
        identity "Test agent with context"

        tool tool
      end
    end

    before do
      allow_any_instance_of(agent_class).to receive(:setup_api_client)
    end

    it 'accepts context in initializer' do
      user = double('User', id: 1)
      school = double('School', id: 100)

      agent = agent_class.new(context: { current_user: user, current_school: school })

      expect(agent.context[:current_user]).to eq(user)
      expect(agent.context[:current_school]).to eq(school)
    end

    it 'defaults to empty context' do
      # Use an agent without tools that require context
      simple_agent_class = Class.new(ActiveIntelligence::Agent) do
        model :claude
        memory :in_memory
      end
      allow_any_instance_of(simple_agent_class).to receive(:setup_api_client)

      agent = simple_agent_class.new
      expect(agent.context).to eq({})
    end

    it 'passes context to tools during instantiation' do
      user = double('User', id: 1)
      school = double('School', id: 100)

      agent = agent_class.new(context: { current_user: user, current_school: school })

      # Tools should have received the context
      tool = agent.tools.first
      expect(tool.context[:current_user]).to eq(user)
      expect(tool.context[:current_school]).to eq(school)
    end
  end

  describe 'tool execution with context' do
    let(:agent_class) do
      tool = scoped_tool_class

      Class.new(ActiveIntelligence::Agent) do
        model :claude
        memory :in_memory
        identity "Test agent"

        tool tool
      end
    end

    let(:user) { double('User', id: 42, name: 'Alice') }
    let(:school) { double('School', id: 123, name: 'Test School') }

    before do
      allow_any_instance_of(agent_class).to receive(:setup_api_client)
    end

    let(:agent) do
      agent_class.new(context: { current_user: user, current_school: school })
    end

    it 'tools can access context during execution' do
      result = agent.send(:execute_tool_call, "find_events", { query: "meeting" })

      expect(result[:success]).to be true
      expect(result[:data][:user_id]).to eq(42)
      expect(result[:data][:school_id]).to eq(123)
      expect(result[:data][:query]).to eq("meeting")
    end

    it 'context is separate from params' do
      # Even if params try to override context, context should remain intact
      result = agent.send(:execute_tool_call, "find_events", {
        query: "test",
        current_user: double('HackerUser', id: 999)  # This should be ignored
      })

      expect(result[:success]).to be true
      expect(result[:data][:user_id]).to eq(42)  # Original context user
    end
  end

  describe 'mixed tools with and without context' do
    let(:agent_class) do
      scoped = scoped_tool_class
      simple = simple_tool_class

      Class.new(ActiveIntelligence::Agent) do
        model :claude
        memory :in_memory
        identity "Mixed agent"

        tool scoped
        tool simple
      end
    end

    before do
      allow_any_instance_of(agent_class).to receive(:setup_api_client)
    end

    it 'handles both types of tools correctly' do
      user = double('User', id: 1)
      school = double('School', id: 100)

      agent = agent_class.new(context: { current_user: user, current_school: school })

      # Scoped tool should use context
      scoped_result = agent.send(:execute_tool_call, "find_events", { query: "test" })
      expect(scoped_result[:data][:user_id]).to eq(1)

      # Simple tool should work without needing context
      simple_result = agent.send(:execute_tool_call, "get_time", {})
      expect(simple_result[:data][:time]).to eq("2024-01-01 12:00:00")
    end
  end

  describe 'context validation at agent level' do
    let(:strict_tool_class) do
      Class.new(ActiveIntelligence::Tool) do
        name "strict_tool"
        context_field :required_value, required: true

        def execute(params)
          success_response({ value: required_value })
        end
      end
    end

    let(:agent_class) do
      tool = strict_tool_class

      Class.new(ActiveIntelligence::Agent) do
        model :claude
        memory :in_memory
        tool tool
      end
    end

    before do
      allow_any_instance_of(agent_class).to receive(:setup_api_client)
    end

    it 'raises error when required context is missing' do
      expect {
        agent_class.new(context: {})  # Missing required_value
      }.to raise_error(ActiveIntelligence::ContextError)
    end

    it 'succeeds when required context is provided' do
      expect {
        agent_class.new(context: { required_value: "test" })
      }.not_to raise_error
    end
  end

  describe 'send_message with context' do
    let(:agent_class) do
      tool = scoped_tool_class

      Class.new(ActiveIntelligence::Agent) do
        model :claude
        memory :in_memory
        identity "Context agent"

        tool tool
      end
    end

    let(:user) { double('User', id: 42) }
    let(:school) { double('School', id: 123) }

    before do
      allow_any_instance_of(agent_class).to receive(:setup_api_client)
    end

    let(:agent) do
      agent_class.new(context: { current_user: user, current_school: school })
    end

    it 'maintains context through tool call loop' do
      # First response: Claude requests tool use
      tool_call_response = ActiveIntelligence::Messages::AgentResponse.new(
        content: "",
        tool_calls: [
          { id: "toolu_123", name: "find_events", parameters: { query: "meeting" } }
        ]
      )

      # Second response: Claude's final response
      final_response = ActiveIntelligence::Messages::AgentResponse.new(
        content: "Found 2 events for your school!",
        tool_calls: []
      )

      allow(agent).to receive(:call_api).and_return(tool_call_response, final_response)

      response = agent.send_message("Find events")

      expect(response).to eq("Found 2 events for your school!")

      # Verify context was used during tool execution
      tool_response = agent.messages.find { |m| m.is_a?(ActiveIntelligence::Messages::ToolResponse) }
      expect(tool_response).not_to be_nil

      # The tool result should contain the context-derived values
      result = tool_response.result || JSON.parse(tool_response.content, symbolize_names: true)
      expect(result[:data][:user_id]).to eq(42)
      expect(result[:data][:school_id]).to eq(123)
    end
  end
end
