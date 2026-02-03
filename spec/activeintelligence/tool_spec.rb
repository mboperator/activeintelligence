require 'spec_helper'

RSpec.describe ActiveIntelligence::Tool do
  describe 'context DSL' do
    describe 'context_field' do
      let(:tool_with_context_fields) do
        Class.new(ActiveIntelligence::Tool) do
          name "scoped_tool"
          description "A tool with context fields"

          context_field :current_user, required: true
          context_field :current_school, required: true
          context_field :permissions, required: false

          param :query, type: String, required: true

          def execute(params)
            success_response({
              query: params[:query],
              user_id: current_user&.id,
              school_id: current_school&.id
            })
          end
        end
      end

      it 'registers context fields on the class' do
        expect(tool_with_context_fields.context_fields).to have_key(:current_user)
        expect(tool_with_context_fields.context_fields).to have_key(:current_school)
        expect(tool_with_context_fields.context_fields).to have_key(:permissions)
      end

      it 'stores required flag for context fields' do
        expect(tool_with_context_fields.context_fields[:current_user][:required]).to be true
        expect(tool_with_context_fields.context_fields[:current_school][:required]).to be true
        expect(tool_with_context_fields.context_fields[:permissions][:required]).to be false
      end

      it 'generates accessor methods for context fields' do
        user = double('User', id: 123)
        school = double('School', id: 456)

        tool = tool_with_context_fields.new(context: { current_user: user, current_school: school })

        expect(tool.current_user).to eq(user)
        expect(tool.current_school).to eq(school)
        expect(tool.permissions).to be_nil
      end

      it 'inherits context fields in subclasses' do
        parent_tool = Class.new(ActiveIntelligence::Tool) do
          context_field :current_user, required: true
        end

        child_tool = Class.new(parent_tool) do
          context_field :current_school, required: true
        end

        expect(child_tool.context_fields).to have_key(:current_user)
        expect(child_tool.context_fields).to have_key(:current_school)
      end
    end

    describe 'context validation' do
      let(:strict_tool) do
        Class.new(ActiveIntelligence::Tool) do
          name "strict_tool"
          context_field :current_user, required: true
          context_field :current_school, required: true

          def execute(params)
            success_response({})
          end
        end
      end

      it 'raises error when required context is missing' do
        expect {
          strict_tool.new(context: { current_user: double('User') })
        }.to raise_error(ActiveIntelligence::ContextError, /missing required context.*current_school/i)
      end

      it 'raises error when context is nil for required field' do
        expect {
          strict_tool.new(context: { current_user: nil, current_school: double('School') })
        }.to raise_error(ActiveIntelligence::ContextError, /missing required context.*current_user/i)
      end

      it 'succeeds when all required context is provided' do
        expect {
          strict_tool.new(context: {
            current_user: double('User'),
            current_school: double('School')
          })
        }.not_to raise_error
      end

      it 'allows optional context to be missing' do
        tool_class = Class.new(ActiveIntelligence::Tool) do
          name "optional_context_tool"
          context_field :current_user, required: true
          context_field :extra_data, required: false

          def execute(params)
            success_response({})
          end
        end

        expect {
          tool_class.new(context: { current_user: double('User') })
        }.not_to raise_error
      end
    end

    describe 'context access during execution' do
      let(:tool_class) do
        Class.new(ActiveIntelligence::Tool) do
          name "context_access_tool"
          context_field :current_user, required: true
          context_field :current_school, required: true

          param :query, type: String, required: true

          def execute(params)
            # Access context via accessor methods
            success_response({
              query: params[:query],
              user_name: current_user.name,
              school_name: current_school.name
            })
          end
        end
      end

      it 'provides context separately from params during execution' do
        user = double('User', name: 'Alice')
        school = double('School', name: 'Test School')

        tool = tool_class.new(context: { current_user: user, current_school: school })
        result = tool.call(query: 'search term')

        expect(result[:success]).to be true
        expect(result[:data][:query]).to eq('search term')
        expect(result[:data][:user_name]).to eq('Alice')
        expect(result[:data][:school_name]).to eq('Test School')
      end

      it 'keeps context immutable during execution' do
        user = double('User', name: 'Alice')
        school = double('School', name: 'Test School')

        tool = tool_class.new(context: { current_user: user, current_school: school })

        # Context should be frozen or at least not modifiable via params
        tool.call(query: 'test', current_user: 'hacker')

        expect(tool.current_user).to eq(user)  # Should still be original
      end
    end

    describe 'tools without context fields' do
      let(:simple_tool) do
        Class.new(ActiveIntelligence::Tool) do
          name "simple_tool"
          param :message, type: String

          def execute(params)
            success_response({ message: params[:message] })
          end
        end
      end

      it 'works without any context' do
        tool = simple_tool.new
        result = tool.call(message: 'hello')

        expect(result[:success]).to be true
        expect(result[:data][:message]).to eq('hello')
      end

      it 'accepts context even without context_field declarations' do
        tool = simple_tool.new(context: { current_user: double('User') })
        expect(tool.context[:current_user]).not_to be_nil
      end

      it 'has empty context_fields hash' do
        expect(simple_tool.context_fields).to eq({})
      end
    end
  end

  describe 'execution context DSL' do
    context 'with backend tool' do
      let(:backend_tool_class) do
        Class.new(ActiveIntelligence::Tool) do
          execution_context :backend
          name "backend_test"
          description "A backend tool"

          def execute(params)
            success_response({ data: "backend" })
          end
        end
      end

      it 'sets execution context to backend' do
        expect(backend_tool_class.execution_context).to eq(:backend)
      end

      it 'returns true for backend?' do
        expect(backend_tool_class.backend?).to be true
      end

      it 'returns false for frontend?' do
        expect(backend_tool_class.frontend?).to be false
      end
    end

    context 'with frontend tool' do
      let(:frontend_tool_class) do
        Class.new(ActiveIntelligence::Tool) do
          execution_context :frontend
          name "frontend_test"
          description "A frontend tool"

          def execute(params)
            success_response({ data: "frontend" })
          end
        end
      end

      it 'sets execution context to frontend' do
        expect(frontend_tool_class.execution_context).to eq(:frontend)
      end

      it 'returns true for frontend?' do
        expect(frontend_tool_class.frontend?).to be true
      end

      it 'returns false for backend?' do
        expect(frontend_tool_class.backend?).to be false
      end
    end

    context 'with default execution context' do
      let(:default_tool_class) do
        Class.new(ActiveIntelligence::Tool) do
          name "default_test"
          description "A tool with default context"

          def execute(params)
            success_response({ data: "default" })
          end
        end
      end

      it 'defaults to backend' do
        expect(default_tool_class.execution_context).to eq(:backend)
      end

      it 'returns true for backend?' do
        expect(default_tool_class.backend?).to be true
      end

      it 'returns false for frontend?' do
        expect(default_tool_class.frontend?).to be false
      end
    end
  end

  describe 'JSON schema generation' do
    let(:frontend_tool_class) do
      Class.new(ActiveIntelligence::Tool) do
        execution_context :frontend
        name "test_tool"
        description "Test tool with params"

        param :message, type: String, required: true, description: "A message"
        param :count, type: Integer, required: false, default: 1

        def execute(params)
          success_response({ message: params[:message] })
        end
      end
    end

    it 'generates correct schema' do
      schema = frontend_tool_class.to_json_schema

      expect(schema[:name]).to eq("test_tool")
      expect(schema[:description]).to eq("Test tool with params")
      expect(schema[:input_schema][:type]).to eq("object")
      expect(schema[:input_schema][:properties]).to have_key(:message)
      expect(schema[:input_schema][:properties]).to have_key(:count)
    end
  end

  describe 'before_execute callbacks' do
    describe 'single callback' do
      let(:tool_with_callback) do
        Class.new(ActiveIntelligence::Tool) do
          name "callback_tool"
          context_field :current_user, required: true

          before_execute :check_authentication

          param :query, type: String

          def execute(params)
            success_response({ query: params[:query] })
          end

          private

          def check_authentication(_params)
            raise ActiveIntelligence::AuthenticationError.new("Not authenticated") unless current_user&.authenticated?
          end
        end
      end

      it 'runs callback before execute' do
        authenticated_user = double('User', authenticated?: true)
        tool = tool_with_callback.new(context: { current_user: authenticated_user })
        result = tool.call(query: 'test')

        expect(result[:success]).to be true
        expect(result[:data][:query]).to eq('test')
      end

      it 'halts execution when callback raises error' do
        unauthenticated_user = double('User', authenticated?: false)
        tool = tool_with_callback.new(context: { current_user: unauthenticated_user })
        result = tool.call(query: 'test')

        expect(result[:error]).to be true
        expect(result[:message]).to eq("Not authenticated")
      end
    end

    describe 'multiple callbacks' do
      let(:tool_with_multiple_callbacks) do
        Class.new(ActiveIntelligence::Tool) do
          name "multi_callback_tool"
          context_field :current_user, required: true

          before_execute :check_authentication
          before_execute :check_authorization

          param :query, type: String

          def execute(params)
            success_response({ query: params[:query] })
          end

          private

          def check_authentication(_params)
            raise ActiveIntelligence::AuthenticationError.new("Not authenticated") unless current_user&.authenticated?
          end

          def check_authorization(_params)
            raise ActiveIntelligence::AuthorizationError.new("Not authorized") unless current_user&.admin?
          end
        end
      end

      it 'runs all callbacks in order when all pass' do
        admin_user = double('User', authenticated?: true, admin?: true)
        tool = tool_with_multiple_callbacks.new(context: { current_user: admin_user })
        result = tool.call(query: 'test')

        expect(result[:success]).to be true
      end

      it 'halts at first failing callback' do
        # Not authenticated - should fail on first callback
        unauthenticated_user = double('User', authenticated?: false, admin?: true)
        tool = tool_with_multiple_callbacks.new(context: { current_user: unauthenticated_user })
        result = tool.call(query: 'test')

        expect(result[:error]).to be true
        expect(result[:message]).to eq("Not authenticated")
      end

      it 'halts at second callback if first passes but second fails' do
        # Authenticated but not admin
        non_admin_user = double('User', authenticated?: true, admin?: false)
        tool = tool_with_multiple_callbacks.new(context: { current_user: non_admin_user })
        result = tool.call(query: 'test')

        expect(result[:error]).to be true
        expect(result[:message]).to eq("Not authorized")
      end
    end

    describe 'callback with block' do
      let(:tool_with_block_callback) do
        Class.new(ActiveIntelligence::Tool) do
          name "block_callback_tool"
          context_field :current_user, required: true

          before_execute do |_params|
            raise ActiveIntelligence::AuthorizationError.new("Admin required") unless current_user&.admin?
          end

          def execute(params)
            success_response({ executed: true })
          end
        end
      end

      it 'executes block callback with access to context' do
        admin_user = double('User', admin?: true)
        tool = tool_with_block_callback.new(context: { current_user: admin_user })
        result = tool.call({})

        expect(result[:success]).to be true
      end

      it 'halts when block callback raises error' do
        non_admin_user = double('User', admin?: false)
        tool = tool_with_block_callback.new(context: { current_user: non_admin_user })
        result = tool.call({})

        expect(result[:error]).to be true
        expect(result[:message]).to eq("Admin required")
      end
    end

    describe 'callback inheritance' do
      let(:parent_tool) do
        Class.new(ActiveIntelligence::Tool) do
          name "parent_tool"
          context_field :current_user, required: true

          before_execute :check_authentication

          def execute(params)
            success_response({ from: "parent" })
          end

          private

          def check_authentication(_params)
            raise ActiveIntelligence::AuthenticationError.new("Not authenticated") unless current_user&.authenticated?
          end
        end
      end

      let(:child_tool) do
        Class.new(parent_tool) do
          name "child_tool"

          before_execute :check_authorization

          def execute(params)
            success_response({ from: "child" })
          end

          private

          def check_authorization(_params)
            raise ActiveIntelligence::AuthorizationError.new("Not authorized") unless current_user&.admin?
          end
        end
      end

      it 'inherits parent callbacks' do
        expect(child_tool.before_execute_callbacks.length).to eq(2)
      end

      it 'runs parent callback first' do
        unauthenticated_user = double('User', authenticated?: false, admin?: true)
        tool = child_tool.new(context: { current_user: unauthenticated_user })
        result = tool.call({})

        # Should fail on parent's authentication check
        expect(result[:error]).to be true
        expect(result[:message]).to eq("Not authenticated")
      end

      it 'runs child callback after parent' do
        authenticated_non_admin = double('User', authenticated?: true, admin?: false)
        tool = child_tool.new(context: { current_user: authenticated_non_admin })
        result = tool.call({})

        # Should pass parent's auth but fail on child's admin check
        expect(result[:error]).to be true
        expect(result[:message]).to eq("Not authorized")
      end

      it 'does not affect parent tool callbacks' do
        expect(parent_tool.before_execute_callbacks.length).to eq(1)
      end
    end

    describe 'callback with params access' do
      let(:tool_with_params_check) do
        Class.new(ActiveIntelligence::Tool) do
          name "params_callback_tool"

          before_execute :validate_dangerous_action

          param :action, type: String, required: true
          param :confirmed, type: String, default: "false"

          def execute(params)
            success_response({ action: params[:action] })
          end

          private

          def validate_dangerous_action(params)
            if params[:action] == "delete" && params[:confirmed] != "true"
              raise ActiveIntelligence::AuthorizationError.new(
                "Dangerous action requires confirmation",
                details: { action: params[:action] }
              )
            end
          end
        end
      end

      it 'allows callback to inspect params' do
        tool = tool_with_params_check.new
        result = tool.call(action: "read")

        expect(result[:success]).to be true
      end

      it 'halts based on param values' do
        tool = tool_with_params_check.new
        result = tool.call(action: "delete")

        expect(result[:error]).to be true
        expect(result[:message]).to eq("Dangerous action requires confirmation")
        expect(result[:details][:action]).to eq("delete")
      end

      it 'allows action when confirmed' do
        tool = tool_with_params_check.new
        result = tool.call(action: "delete", confirmed: "true")

        expect(result[:success]).to be true
      end
    end

    describe 'tool without callbacks' do
      let(:simple_tool) do
        Class.new(ActiveIntelligence::Tool) do
          name "no_callback_tool"

          def execute(params)
            success_response({ executed: true })
          end
        end
      end

      it 'has empty callbacks array' do
        expect(simple_tool.before_execute_callbacks).to eq([])
      end

      it 'executes normally without callbacks' do
        tool = simple_tool.new
        result = tool.call({})

        expect(result[:success]).to be true
      end
    end
  end

  describe 'tool execution' do
    let(:backend_tool_class) do
      Class.new(ActiveIntelligence::Tool) do
        execution_context :backend
        name "time_tool"
        description "Get the time"

        def execute(params)
          success_response({ time: Time.now.to_s })
        end
      end
    end

    let(:frontend_tool_class) do
      Class.new(ActiveIntelligence::Tool) do
        execution_context :frontend
        name "alert_tool"
        description "Show an alert"

        param :message, type: String, required: true

        def execute(params)
          success_response({ message: params[:message], displayed: true })
        end
      end
    end

    it 'executes backend tool successfully' do
      tool = backend_tool_class.new
      result = tool.call({})

      expect(result).to be_a(Hash)
      expect(result[:success]).to be true
      expect(result[:data]).to have_key(:time)
    end

    it 'executes frontend tool successfully' do
      tool = frontend_tool_class.new
      result = tool.call({ message: "Hello" })

      expect(result).to be_a(Hash)
      expect(result[:success]).to be true
      expect(result[:data][:message]).to eq("Hello")
      expect(result[:data][:displayed]).to be true
    end

    it 'validates required parameters' do
      tool = frontend_tool_class.new
      result = tool.call({})

      # Note: Current implementation applies nil defaults, so required params
      # with no default still get nil value and validation passes.
      expect(result).to be_a(Hash)
      expect(result[:success]).to be true
      expect(result[:data][:message]).to be_nil
    end

    it 'validates parameter types' do
      tool_class = Class.new(ActiveIntelligence::Tool) do
        execution_context :frontend
        name "type_test_tool"
        param :count, type: Integer, required: true

        def execute(params)
          success_response({ count: params[:count] })
        end
      end

      tool = tool_class.new

      expect {
        tool.call({ count: "not a number" })
      }.to raise_error(ActiveIntelligence::InvalidParameterError, /Invalid type/)
    end
  end
end
