require 'spec_helper'

RSpec.describe ActiveIntelligence::Callbacks do
  describe 'data structures' do
    describe ActiveIntelligence::Session do
      subject(:session) { described_class.new(agent_class: 'TestAgent') }

      it 'generates a unique id' do
        expect(session.id).to be_a(String)
        expect(session.id.length).to eq(36) # UUID format
      end

      it 'sets agent_class' do
        expect(session.agent_class).to eq('TestAgent')
      end

      it 'initializes with zero counters' do
        expect(session.total_turns).to eq(0)
        expect(session.total_input_tokens).to eq(0)
        expect(session.total_output_tokens).to eq(0)
      end

      it 'tracks duration when ended' do
        expect(session.duration).to be_nil
        session.end!
        expect(session.duration).to be >= 0
      end

      it 'converts to hash' do
        hash = session.to_h
        expect(hash).to include(:id, :agent_class, :created_at, :total_turns)
      end
    end

    describe ActiveIntelligence::Turn do
      subject(:turn) { described_class.new(user_message: 'Hello', session_id: 'session-123') }

      it 'generates a unique id' do
        expect(turn.id).to be_a(String)
      end

      it 'stores user_message' do
        expect(turn.user_message).to eq('Hello')
      end

      it 'stores session_id' do
        expect(turn.session_id).to eq('session-123')
      end

      it 'initializes with zero iteration count' do
        expect(turn.iteration_count).to eq(0)
      end

      it 'tracks duration when ended' do
        expect(turn.duration).to be_nil
        turn.end!
        expect(turn.duration).to be >= 0
      end
    end

    describe ActiveIntelligence::Response do
      subject(:response) { described_class.new(turn_id: 'turn-123', is_streaming: true) }

      it 'generates a unique id' do
        expect(response.id).to be_a(String)
      end

      it 'stores turn_id and is_streaming' do
        expect(response.turn_id).to eq('turn-123')
        expect(response.is_streaming).to be true
      end

      it 'tracks duration when ended' do
        expect(response.duration).to be_nil
        response.end!
        expect(response.duration).to be >= 0
      end
    end

    describe ActiveIntelligence::ToolExecution do
      subject(:tool_exec) do
        described_class.new(
          name: 'my_tool',
          tool_class: 'MyTool',
          input: { query: 'test' },
          tool_use_id: 'toolu_123'
        )
      end

      it 'stores tool metadata' do
        expect(tool_exec.name).to eq('my_tool')
        expect(tool_exec.tool_class).to eq('MyTool')
        expect(tool_exec.input).to eq({ query: 'test' })
        expect(tool_exec.tool_use_id).to eq('toolu_123')
      end

      it 'tracks success state' do
        tool_exec.result = { success: true, data: {} }
        tool_exec.end!
        expect(tool_exec.success?).to be true
      end

      it 'tracks error state' do
        tool_exec.error = StandardError.new('Something went wrong')
        tool_exec.end!
        expect(tool_exec.success?).to be false
      end
    end

    describe ActiveIntelligence::Usage do
      subject(:usage) { described_class.new(input_tokens: 100, output_tokens: 50) }

      it 'stores token counts' do
        expect(usage.input_tokens).to eq(100)
        expect(usage.output_tokens).to eq(50)
      end

      it 'calculates total_tokens' do
        expect(usage.total_tokens).to eq(150)
      end

      it 'can add another usage' do
        other = described_class.new(input_tokens: 25, output_tokens: 25)
        usage.add(other)
        expect(usage.input_tokens).to eq(125)
        expect(usage.output_tokens).to eq(75)
      end
    end

    describe ActiveIntelligence::Chunk do
      subject(:chunk) { described_class.new(content: 'Hello', index: 0, response_id: 'resp-123') }

      it 'stores chunk data' do
        expect(chunk.content).to eq('Hello')
        expect(chunk.index).to eq(0)
        expect(chunk.response_id).to eq('resp-123')
      end
    end

    describe ActiveIntelligence::Iteration do
      subject(:iteration) { described_class.new(number: 1, tool_calls_count: 2, turn_id: 'turn-123') }

      it 'stores iteration data' do
        expect(iteration.number).to eq(1)
        expect(iteration.tool_calls_count).to eq(2)
        expect(iteration.turn_id).to eq('turn-123')
      end
    end

    describe ActiveIntelligence::ErrorContext do
      let(:error) { StandardError.new('Test error') }
      subject(:context) { described_class.new(error: error, context: { turn_id: '123' }) }

      it 'stores error details' do
        expect(context.error_class).to eq('StandardError')
        expect(context.message).to eq('Test error')
      end

      it 'stores context hash' do
        expect(context.context).to eq({ turn_id: '123' })
      end
    end

    describe ActiveIntelligence::StopEvent do
      subject(:event) { described_class.new(reason: :complete, details: { final: true }) }

      it 'stores reason and details' do
        expect(event.reason).to eq(:complete)
        expect(event.details).to eq({ final: true })
      end
    end
  end

  describe 'callback registration and triggering' do
    let(:test_agent_class) do
      Class.new(ActiveIntelligence::Agent) do
        model :claude
        memory :in_memory
        identity "Test agent"
      end
    end

    describe 'block-based callbacks' do
      it 'registers and triggers on_session_start' do
        session_received = nil
        test_agent_class.on_session_start { |session| session_received = session }

        agent = create_agent(test_agent_class)

        expect(session_received).to be_a(ActiveIntelligence::Session)
        expect(session_received.agent_class).to eq(test_agent_class.name)
      end

      it 'registers and triggers on_session_end' do
        session_received = nil
        test_agent_class.on_session_end { |session| session_received = session }

        agent = create_agent(test_agent_class)
        agent.end_session

        expect(session_received).to be_a(ActiveIntelligence::Session)
        expect(session_received.ended_at).not_to be_nil
      end

      it 'registers and triggers on_turn_start' do
        turn_received = nil
        test_agent_class.on_turn_start { |turn| turn_received = turn }

        agent = create_agent(test_agent_class)
        mock_simple_response(agent)

        agent.send_message('Hello')

        expect(turn_received).to be_a(ActiveIntelligence::Turn)
        expect(turn_received.user_message).to eq('Hello')
      end

      it 'registers and triggers on_turn_end' do
        turn_received = nil
        test_agent_class.on_turn_end { |turn| turn_received = turn }

        agent = create_agent(test_agent_class)
        mock_simple_response(agent)

        agent.send_message('Hello')

        expect(turn_received).to be_a(ActiveIntelligence::Turn)
        expect(turn_received.ended_at).not_to be_nil
      end

      it 'registers and triggers on_response_start and on_response_end' do
        response_started = nil
        response_ended = nil

        test_agent_class.on_response_start { |r| response_started = r }
        test_agent_class.on_response_end { |r| response_ended = r }

        agent = create_agent(test_agent_class)
        mock_api_client_response(agent)

        agent.send_message('Hello')

        expect(response_started).to be_a(ActiveIntelligence::Response)
        expect(response_ended).to be_a(ActiveIntelligence::Response)
        expect(response_ended.ended_at).not_to be_nil
      end

      it 'registers and triggers on_message_added' do
        messages_added = []
        test_agent_class.on_message_added { |msg| messages_added << msg }

        agent = create_agent(test_agent_class)
        mock_simple_response(agent)

        agent.send_message('Hello')

        expect(messages_added.size).to eq(2) # UserMessage + AgentResponse
        expect(messages_added[0]).to be_a(ActiveIntelligence::Messages::UserMessage)
        expect(messages_added[1]).to be_a(ActiveIntelligence::Messages::AgentResponse)
      end

      it 'registers and triggers on_stop' do
        stop_event = nil
        test_agent_class.on_stop { |event| stop_event = event }

        agent = create_agent(test_agent_class)
        mock_simple_response(agent)

        agent.send_message('Hello')

        expect(stop_event).to be_a(ActiveIntelligence::StopEvent)
        expect(stop_event.reason).to eq(:complete)
      end
    end

    describe 'method-based callbacks' do
      let(:agent_with_methods) do
        Class.new(ActiveIntelligence::Agent) do
          model :claude
          memory :in_memory
          identity "Test agent"

          on_session_start :handle_session_start
          on_turn_start :handle_turn_start

          attr_reader :session_started, :turn_started

          def handle_session_start(session)
            @session_started = session
          end

          def handle_turn_start(turn)
            @turn_started = turn
          end
        end
      end

      it 'calls the named method for callbacks' do
        agent = create_agent(agent_with_methods)
        mock_simple_response(agent)

        agent.send_message('Hello')

        expect(agent.session_started).to be_a(ActiveIntelligence::Session)
        expect(agent.turn_started).to be_a(ActiveIntelligence::Turn)
      end
    end

    describe 'callback inheritance' do
      let(:parent_class) do
        Class.new(ActiveIntelligence::Agent) do
          model :claude
          memory :in_memory
          identity "Parent"

          class << self
            attr_accessor :parent_called
          end

          on_session_start { self.class.parent_called = true }
        end
      end

      let(:child_class) do
        parent = parent_class
        Class.new(parent) do
          class << self
            attr_accessor :child_called
          end

          on_session_start { self.class.child_called = true }
        end
      end

      it 'inherits parent callbacks to child' do
        agent = create_agent(child_class)

        # Both parent and child callbacks should be called
        expect(child_class.parent_called).to be true
        expect(child_class.child_called).to be true
      end
    end
  end

  describe 'tool callbacks' do
    let(:test_tool_class) do
      Class.new(ActiveIntelligence::Tool) do
        execution_context :backend
        name "test_tool"
        description "A test tool"

        param :query, type: String, required: true

        def execute(params)
          success_response({ result: "executed" })
        end
      end
    end

    let(:test_agent_class) do
      tool_class = test_tool_class
      Class.new(ActiveIntelligence::Agent) do
        model :claude
        memory :in_memory
        identity "Test agent"
        tool tool_class
      end
    end

    it 'triggers on_tool_start and on_tool_end' do
      tool_started = nil
      tool_ended = nil

      test_agent_class.on_tool_start { |t| tool_started = t }
      test_agent_class.on_tool_end { |t| tool_ended = t }

      agent = create_agent(test_agent_class)
      mock_tool_response(agent)

      agent.send_message('Use the tool')

      expect(tool_started).to be_a(ActiveIntelligence::ToolExecution)
      expect(tool_started.name).to eq('test_tool')
      expect(tool_ended).to be_a(ActiveIntelligence::ToolExecution)
      expect(tool_ended.result).to include(:success)
    end

    it 'triggers on_iteration during tool loop' do
      iterations = []
      test_agent_class.on_iteration { |iter| iterations << iter }

      agent = create_agent(test_agent_class)
      mock_tool_response(agent)

      agent.send_message('Use the tool')

      expect(iterations.size).to eq(1)
      expect(iterations[0].number).to eq(1)
      expect(iterations[0].tool_calls_count).to eq(1)
    end
  end

  describe 'error callbacks' do
    # Tool that returns an error response (caught internally by Tool class)
    let(:failing_tool_class) do
      Class.new(ActiveIntelligence::Tool) do
        execution_context :backend
        name "failing_tool"
        description "A tool that fails"

        param :query, type: String, required: true

        def execute(params)
          raise StandardError, "Tool failure!"
        end
      end
    end

    let(:test_agent_class) do
      tool_class = failing_tool_class
      Class.new(ActiveIntelligence::Agent) do
        model :claude
        memory :in_memory
        identity "Test agent"
        tool tool_class
      end
    end

    it 'triggers on_tool_error when tool returns error response' do
      tool_errors = []
      test_agent_class.on_tool_error { |t| tool_errors << t }

      agent = create_agent(test_agent_class)

      # Mock the API client: first call returns tool_use, second returns final text
      api_client = double('api_client')
      agent.instance_variable_set(:@api_client, api_client)

      call_count = 0
      allow(api_client).to receive(:call) do
        call_count += 1
        if call_count == 1
          {
            content: "",
            tool_calls: [{ id: "toolu_123", name: "failing_tool", parameters: { query: "test" } }],
            stop_reason: "tool_use",
            usage: nil,
            thinking: nil,
            model: "claude-3"
          }
        else
          {
            content: "I see the tool failed.",
            tool_calls: [],
            stop_reason: "end_turn",
            usage: nil,
            thinking: nil,
            model: "claude-3"
          }
        end
      end

      # Tool errors are caught by the Tool class and returned as error responses
      # So no exception is raised, but on_tool_error is fired
      agent.send_message('Use the tool')

      expect(tool_errors.size).to eq(1)
      expect(tool_errors.first).to be_a(ActiveIntelligence::ToolExecution)
      expect(tool_errors.first.result).to include(:error)
      expect(tool_errors.first.result[:message]).to include("Tool failure!")
    end

    it 'triggers on_error for agent-level errors like max iterations' do
      error_context = nil
      test_agent_class.on_error { |ctx| error_context = ctx }

      agent = create_agent(test_agent_class)

      # Mock the API client to always return tool calls (infinite loop)
      api_client = double('api_client')
      agent.instance_variable_set(:@api_client, api_client)

      # Use unique tool_use_ids to force loop to continue
      call_count = 0
      allow(api_client).to receive(:call) do
        call_count += 1
        {
          content: "",
          tool_calls: [{ id: "toolu_#{call_count}", name: "failing_tool", parameters: { query: "test" } }],
          stop_reason: "tool_use",
          usage: nil,
          thinking: nil,
          model: "claude-3"
        }
      end

      expect { agent.send_message('Use the tool') }.to raise_error(ActiveIntelligence::Error, /Maximum tool call iterations/)

      expect(error_context).to be_a(ActiveIntelligence::ErrorContext)
      expect(error_context.message).to include("Maximum tool call iterations")
    end
  end

  describe 'usage tracking' do
    let(:test_agent_class) do
      Class.new(ActiveIntelligence::Agent) do
        model :claude
        memory :in_memory
        identity "Test agent"
      end
    end

    it 'accumulates usage in session' do
      agent = create_agent(test_agent_class)
      mock_api_client_with_usage(agent, input: 100, output: 50)

      agent.send_message('Hello')

      expect(agent.session.total_input_tokens).to eq(100)
      expect(agent.session.total_output_tokens).to eq(50)
    end

    it 'tracks usage in turn' do
      turn_ended = nil
      test_agent_class.on_turn_end { |t| turn_ended = t }

      agent = create_agent(test_agent_class)
      mock_api_client_with_usage(agent, input: 100, output: 50)

      agent.send_message('Hello')

      expect(turn_ended.usage.input_tokens).to eq(100)
      expect(turn_ended.usage.output_tokens).to eq(50)
    end

    it 'tracks usage in response' do
      response_ended = nil
      test_agent_class.on_response_end { |r| response_ended = r }

      agent = create_agent(test_agent_class)
      mock_api_client_with_usage(agent, input: 100, output: 50)

      agent.send_message('Hello')

      expect(response_ended.usage.input_tokens).to eq(100)
      expect(response_ended.usage.output_tokens).to eq(50)
    end
  end

  # Helper methods
  def create_agent(agent_class)
    agent = agent_class.allocate
    allow(agent).to receive(:setup_api_client)
    agent.send(:initialize)
    agent
  end

  def mock_simple_response(agent)
    allow(agent).to receive(:call_api).and_return(
      ActiveIntelligence::Messages::AgentResponse.new(
        content: "Hello!",
        tool_calls: []
      )
    )
  end

  def mock_api_client_response(agent, content: "Hello!", usage: nil)
    api_client = double('api_client')
    agent.instance_variable_set(:@api_client, api_client)

    allow(api_client).to receive(:call).and_return({
      content: content,
      tool_calls: [],
      stop_reason: "end_turn",
      usage: usage,
      thinking: nil,
      model: "claude-3"
    })
  end

  def mock_api_client_with_usage(agent, input:, output:)
    api_client = double('api_client')
    agent.instance_variable_set(:@api_client, api_client)

    usage = ActiveIntelligence::Usage.new(input_tokens: input, output_tokens: output)

    allow(api_client).to receive(:call).and_return({
      content: "Hello!",
      tool_calls: [],
      stop_reason: "end_turn",
      usage: usage,
      thinking: nil,
      model: "claude-3"
    })
  end

  def mock_tool_response(agent)
    tool_call_response = ActiveIntelligence::Messages::AgentResponse.new(
      content: "",
      tool_calls: [
        { id: "toolu_123", name: "test_tool", parameters: { query: "test" } }
      ]
    )

    final_response = ActiveIntelligence::Messages::AgentResponse.new(
      content: "Done!",
      tool_calls: []
    )

    allow(agent).to receive(:call_api).and_return(tool_call_response, final_response)
  end

  def mock_failing_tool_response(agent)
    tool_call_response = ActiveIntelligence::Messages::AgentResponse.new(
      content: "",
      tool_calls: [
        { id: "toolu_123", name: "failing_tool", parameters: { query: "test" } }
      ]
    )

    allow(agent).to receive(:call_api).and_return(tool_call_response)
  end
end
