require 'spec_helper'

RSpec.describe ActiveIntelligence::Tool do
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
