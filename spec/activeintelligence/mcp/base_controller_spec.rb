# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'time'

# Stub ActionController::API for testing without Rails
unless defined?(ActionController::API)
  module ActionController
    class API
      def self.inherited(subclass)
        # no-op for testing
      end
    end
  end
end

# Now we can require the MCP BaseController
require_relative '../../../lib/activeintelligence/mcp/base_controller'

# MCP Protocol Specification: https://modelcontextprotocol.io/specification/2025-11-25
#
# These tests verify that the BaseController implementation correctly fulfills
# the Model Context Protocol (MCP) specification. Tests are organized by protocol
# component and reference specific sections of the spec.

RSpec.describe ActiveIntelligence::MCP::BaseController do
  # Test fixtures: sample tools for testing
  let(:calculator_tool) do
    Class.new(ActiveIntelligence::Tool) do
      name 'calculate_sum'
      description 'Add two numbers together'

      param :a, type: Integer, required: true, description: 'First number'
      param :b, type: Integer, required: true, description: 'Second number'

      def execute(params)
        success_response({ result: params[:a] + params[:b] })
      end
    end
  end

  let(:greeting_tool) do
    Class.new(ActiveIntelligence::Tool) do
      name 'greet'
      description 'Generate a greeting message'

      param :name, type: String, required: true, description: 'Name to greet'
      param :formal, type: TrueClass, required: false, default: false, description: 'Use formal greeting'

      def execute(params)
        greeting = params[:formal] ? "Good day, #{params[:name]}." : "Hey #{params[:name]}!"
        success_response({ message: greeting })
      end
    end
  end

  let(:failing_tool) do
    Class.new(ActiveIntelligence::Tool) do
      name 'always_fails'
      description 'A tool that always fails for testing'

      def execute(_params)
        raise StandardError, 'Intentional failure for testing'
      end

      rescue_from StandardError do |e, _params|
        error_response('Tool execution failed', details: e.message)
      end
    end
  end

  let(:no_params_tool) do
    Class.new(ActiveIntelligence::Tool) do
      name 'get_current_time'
      description 'Returns the current server time'

      def execute(_params)
        success_response({ time: Time.now.iso8601 })
      end
    end
  end

  # Controller subclass for testing
  let(:controller_class) do
    tools = [calculator_tool, greeting_tool, no_params_tool]
    Class.new(ActiveIntelligence::MCP::BaseController) do
      @_mcp_tools = tools

      def self._mcp_tools
        @_mcp_tools
      end
    end
  end

  let(:controller) { controller_class.new }

  # Helper to simulate JSON-RPC request
  def jsonrpc_request(method:, id: 1, params: nil)
    request = {
      'jsonrpc' => '2.0',
      'id' => id,
      'method' => method
    }
    request['params'] = params if params
    request
  end

  def jsonrpc_notification(method:, params: nil)
    notification = {
      'jsonrpc' => '2.0',
      'method' => method
    }
    notification['params'] = params if params
    notification
  end

  # ============================================================================
  # Section 1: JSON-RPC 2.0 Base Protocol Compliance
  # Spec: https://modelcontextprotocol.io/specification/2025-11-25/basic
  # ============================================================================

  describe 'JSON-RPC 2.0 Base Protocol' do
    describe 'request format validation' do
      it 'accepts valid JSON-RPC 2.0 requests with string id' do
        request = jsonrpc_request(method: 'ping', id: 'abc-123')
        response = controller.handle_request(request)

        expect(response['jsonrpc']).to eq('2.0')
        expect(response['id']).to eq('abc-123')
      end

      it 'accepts valid JSON-RPC 2.0 requests with integer id' do
        request = jsonrpc_request(method: 'ping', id: 42)
        response = controller.handle_request(request)

        expect(response['jsonrpc']).to eq('2.0')
        expect(response['id']).to eq(42)
      end

      it 'rejects requests with null id (MCP requirement)' do
        # MCP spec: "Unlike base JSON-RPC, the ID MUST NOT be null"
        request = { 'jsonrpc' => '2.0', 'id' => nil, 'method' => 'ping' }
        response = controller.handle_request(request)

        expect(response['error']).not_to be_nil
        expect(response['error']['code']).to eq(-32600) # Invalid Request
      end

      it 'rejects requests without jsonrpc field' do
        request = { 'id' => 1, 'method' => 'ping' }
        response = controller.handle_request(request)

        expect(response['error']).not_to be_nil
        expect(response['error']['code']).to eq(-32600)
      end

      it 'rejects requests with wrong jsonrpc version' do
        request = { 'jsonrpc' => '1.0', 'id' => 1, 'method' => 'ping' }
        response = controller.handle_request(request)

        expect(response['error']).not_to be_nil
        expect(response['error']['code']).to eq(-32600)
      end

      it 'rejects requests without method field' do
        request = { 'jsonrpc' => '2.0', 'id' => 1 }
        response = controller.handle_request(request)

        expect(response['error']).not_to be_nil
        expect(response['error']['code']).to eq(-32600)
      end
    end

    describe 'response format' do
      it 'includes jsonrpc version 2.0 in all responses' do
        request = jsonrpc_request(method: 'ping')
        response = controller.handle_request(request)

        expect(response['jsonrpc']).to eq('2.0')
      end

      it 'echoes back the request id in responses' do
        request = jsonrpc_request(method: 'ping', id: 'unique-id-123')
        response = controller.handle_request(request)

        expect(response['id']).to eq('unique-id-123')
      end

      it 'includes result field for successful responses' do
        request = jsonrpc_request(method: 'ping')
        response = controller.handle_request(request)

        expect(response).to have_key('result')
        expect(response).not_to have_key('error')
      end

      it 'includes error field for error responses' do
        request = jsonrpc_request(method: 'nonexistent_method')
        response = controller.handle_request(request)

        expect(response).to have_key('error')
        expect(response).not_to have_key('result')
      end
    end

    describe 'error response format' do
      it 'includes code and message in error responses' do
        request = jsonrpc_request(method: 'nonexistent_method')
        response = controller.handle_request(request)

        expect(response['error']['code']).to be_an(Integer)
        expect(response['error']['message']).to be_a(String)
      end

      it 'returns -32601 for unknown methods (Method not found)' do
        request = jsonrpc_request(method: 'unknown_method_xyz')
        response = controller.handle_request(request)

        expect(response['error']['code']).to eq(-32601)
      end

      it 'returns -32700 for malformed JSON (Parse error)' do
        response = controller.handle_raw_request('{ invalid json }')

        expect(response['error']['code']).to eq(-32700)
      end

      it 'returns -32602 for invalid params' do
        # Initialize first
        controller.handle_request(jsonrpc_request(
          method: 'initialize',
          params: {
            'protocolVersion' => '2025-11-25',
            'capabilities' => {},
            'clientInfo' => { 'name' => 'Test', 'version' => '1.0' }
          }
        ))
        controller.handle_request(jsonrpc_notification(method: 'notifications/initialized'))

        # tools/call with missing required 'name' param
        request = jsonrpc_request(method: 'tools/call', params: { 'arguments' => {} })
        response = controller.handle_request(request)

        expect(response['error']['code']).to eq(-32602)
      end
    end

    describe 'notification handling' do
      it 'does not send a response for notifications (no id)' do
        notification = jsonrpc_notification(method: 'notifications/initialized')
        response = controller.handle_request(notification)

        expect(response).to be_nil
      end
    end
  end

  # ============================================================================
  # Section 2: Lifecycle - Initialization
  # Spec: https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle
  # ============================================================================

  describe 'Lifecycle: Initialize' do
    let(:valid_initialize_params) do
      {
        'protocolVersion' => '2025-11-25',
        'capabilities' => {},
        'clientInfo' => {
          'name' => 'TestClient',
          'version' => '1.0.0'
        }
      }
    end

    describe 'initialize request' do
      it 'accepts valid initialize request' do
        request = jsonrpc_request(method: 'initialize', params: valid_initialize_params)
        response = controller.handle_request(request)

        expect(response['result']).to be_a(Hash)
        expect(response['error']).to be_nil
      end

      it 'returns protocolVersion in response' do
        request = jsonrpc_request(method: 'initialize', params: valid_initialize_params)
        response = controller.handle_request(request)

        expect(response['result']['protocolVersion']).to be_a(String)
      end

      it 'returns server capabilities in response' do
        request = jsonrpc_request(method: 'initialize', params: valid_initialize_params)
        response = controller.handle_request(request)

        expect(response['result']['capabilities']).to be_a(Hash)
      end

      it 'declares tools capability when tools are registered' do
        request = jsonrpc_request(method: 'initialize', params: valid_initialize_params)
        response = controller.handle_request(request)

        expect(response['result']['capabilities']['tools']).to be_a(Hash)
      end

      it 'returns serverInfo in response' do
        request = jsonrpc_request(method: 'initialize', params: valid_initialize_params)
        response = controller.handle_request(request)

        expect(response['result']['serverInfo']).to be_a(Hash)
        expect(response['result']['serverInfo']['name']).to be_a(String)
      end

      it 'optionally includes instructions in response' do
        request = jsonrpc_request(method: 'initialize', params: valid_initialize_params)
        response = controller.handle_request(request)

        # instructions is optional, so we just verify format if present
        if response['result']['instructions']
          expect(response['result']['instructions']).to be_a(String)
        end
      end
    end

    describe 'protocol version negotiation' do
      it 'responds with same version if supported' do
        request = jsonrpc_request(method: 'initialize', params: valid_initialize_params)
        response = controller.handle_request(request)

        expect(response['result']['protocolVersion']).to eq('2025-11-25')
      end

      it 'responds with supported version if requested version is not supported' do
        params = valid_initialize_params.merge('protocolVersion' => '1.0.0')
        request = jsonrpc_request(method: 'initialize', params: params)
        response = controller.handle_request(request)

        # Should either return an error or a supported version
        if response['error']
          expect(response['error']['code']).to eq(-32602)
        else
          expect(response['result']['protocolVersion']).not_to eq('1.0.0')
        end
      end
    end

    describe 'initialized notification' do
      it 'accepts initialized notification after successful initialize' do
        # First, initialize
        init_request = jsonrpc_request(method: 'initialize', params: valid_initialize_params)
        controller.handle_request(init_request)

        # Then send initialized notification
        notification = jsonrpc_notification(method: 'notifications/initialized')
        response = controller.handle_request(notification)

        # Notifications should not receive a response
        expect(response).to be_nil
      end

      it 'marks session as ready after initialized notification' do
        init_request = jsonrpc_request(method: 'initialize', params: valid_initialize_params)
        controller.handle_request(init_request)

        notification = jsonrpc_notification(method: 'notifications/initialized')
        controller.handle_request(notification)

        expect(controller.session_initialized?).to be true
      end
    end

    describe 'lifecycle enforcement' do
      it 'rejects tools/list before initialization' do
        request = jsonrpc_request(method: 'tools/list')
        response = controller.handle_request(request)

        expect(response['error']).not_to be_nil
        expect(response['error']['message']).to match(/not initialized/i)
      end

      it 'rejects tools/call before initialization' do
        request = jsonrpc_request(
          method: 'tools/call',
          params: { 'name' => 'calculate_sum', 'arguments' => { 'a' => 1, 'b' => 2 } }
        )
        response = controller.handle_request(request)

        expect(response['error']).not_to be_nil
      end

      it 'allows ping before initialization' do
        # Spec: "The client SHOULD NOT send requests other than pings before
        # the server has responded to the initialize request"
        request = jsonrpc_request(method: 'ping')
        response = controller.handle_request(request)

        expect(response['result']).to eq({})
        expect(response['error']).to be_nil
      end
    end
  end

  # ============================================================================
  # Section 3: Ping
  # Spec: https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/ping
  # ============================================================================

  describe 'Ping' do
    it 'responds with empty result object' do
      request = jsonrpc_request(method: 'ping')
      response = controller.handle_request(request)

      expect(response['result']).to eq({})
    end

    it 'works with string id' do
      request = jsonrpc_request(method: 'ping', id: 'ping-123')
      response = controller.handle_request(request)

      expect(response['id']).to eq('ping-123')
      expect(response['result']).to eq({})
    end

    it 'works with integer id' do
      request = jsonrpc_request(method: 'ping', id: 999)
      response = controller.handle_request(request)

      expect(response['id']).to eq(999)
      expect(response['result']).to eq({})
    end
  end

  # ============================================================================
  # Section 4: Tools - Listing
  # Spec: https://modelcontextprotocol.io/specification/2025-11-25/server/tools
  # ============================================================================

  describe 'Tools: tools/list' do
    before do
      # Initialize the session first
      init_request = jsonrpc_request(
        method: 'initialize',
        params: {
          'protocolVersion' => '2025-11-25',
          'capabilities' => {},
          'clientInfo' => { 'name' => 'Test', 'version' => '1.0' }
        }
      )
      controller.handle_request(init_request)
      controller.handle_request(jsonrpc_notification(method: 'notifications/initialized'))
    end

    it 'returns a list of tools' do
      request = jsonrpc_request(method: 'tools/list')
      response = controller.handle_request(request)

      expect(response['result']['tools']).to be_an(Array)
    end

    it 'includes all registered tools' do
      request = jsonrpc_request(method: 'tools/list')
      response = controller.handle_request(request)

      tool_names = response['result']['tools'].map { |t| t['name'] }
      expect(tool_names).to include('calculate_sum')
      expect(tool_names).to include('greet')
      expect(tool_names).to include('get_current_time')
    end

    describe 'tool definition format' do
      let(:tools_response) do
        request = jsonrpc_request(method: 'tools/list')
        controller.handle_request(request)['result']['tools']
      end

      it 'includes name for each tool' do
        tools_response.each do |tool|
          expect(tool['name']).to be_a(String)
          expect(tool['name']).not_to be_empty
        end
      end

      it 'includes description for each tool' do
        tools_response.each do |tool|
          expect(tool['description']).to be_a(String)
        end
      end

      it 'includes inputSchema for each tool' do
        tools_response.each do |tool|
          expect(tool['inputSchema']).to be_a(Hash)
          expect(tool['inputSchema']['type']).to eq('object')
        end
      end

      it 'has valid JSON Schema for tool with parameters' do
        calc_tool = tools_response.find { |t| t['name'] == 'calculate_sum' }

        expect(calc_tool['inputSchema']['properties']).to be_a(Hash)
        expect(calc_tool['inputSchema']['properties']['a']).to be_a(Hash)
        expect(calc_tool['inputSchema']['properties']['b']).to be_a(Hash)
        expect(calc_tool['inputSchema']['required']).to include('a', 'b')
      end

      it 'has valid JSON Schema for tool without parameters' do
        time_tool = tools_response.find { |t| t['name'] == 'get_current_time' }

        # Spec: "For tools with no parameters, use { type: 'object', additionalProperties: false }"
        expect(time_tool['inputSchema']['type']).to eq('object')
      end

      it 'uses correct JSON Schema types' do
        calc_tool = tools_response.find { |t| t['name'] == 'calculate_sum' }

        expect(calc_tool['inputSchema']['properties']['a']['type']).to eq('integer')
        expect(calc_tool['inputSchema']['properties']['b']['type']).to eq('integer')
      end

      it 'includes parameter descriptions in schema' do
        calc_tool = tools_response.find { |t| t['name'] == 'calculate_sum' }

        expect(calc_tool['inputSchema']['properties']['a']['description']).to eq('First number')
      end
    end

    describe 'tool name validation' do
      # Spec: Tool names SHOULD be between 1 and 128 characters
      # Allowed characters: A-Z, a-z, 0-9, _, -, .

      it 'returns tools with valid names' do
        request = jsonrpc_request(method: 'tools/list')
        response = controller.handle_request(request)

        response['result']['tools'].each do |tool|
          expect(tool['name']).to match(/\A[a-zA-Z0-9_\-.]+\z/)
          expect(tool['name'].length).to be_between(1, 128)
        end
      end
    end

    describe 'pagination support' do
      it 'accepts optional cursor parameter' do
        request = jsonrpc_request(method: 'tools/list', params: { 'cursor' => 'abc' })
        response = controller.handle_request(request)

        # Should not error on cursor param
        expect(response['error']).to be_nil
      end

      it 'may include nextCursor for pagination' do
        request = jsonrpc_request(method: 'tools/list')
        response = controller.handle_request(request)

        # nextCursor is optional
        if response['result']['nextCursor']
          expect(response['result']['nextCursor']).to be_a(String)
        end
      end
    end
  end

  # ============================================================================
  # Section 5: Tools - Calling
  # Spec: https://modelcontextprotocol.io/specification/2025-11-25/server/tools
  # ============================================================================

  describe 'Tools: tools/call' do
    before do
      # Initialize the session first
      init_request = jsonrpc_request(
        method: 'initialize',
        params: {
          'protocolVersion' => '2025-11-25',
          'capabilities' => {},
          'clientInfo' => { 'name' => 'Test', 'version' => '1.0' }
        }
      )
      controller.handle_request(init_request)
      controller.handle_request(jsonrpc_notification(method: 'notifications/initialized'))
    end

    describe 'request format' do
      it 'requires name parameter' do
        request = jsonrpc_request(
          method: 'tools/call',
          params: { 'arguments' => {} }
        )
        response = controller.handle_request(request)

        expect(response['error']).not_to be_nil
        expect(response['error']['code']).to eq(-32602)
      end

      it 'accepts arguments parameter' do
        request = jsonrpc_request(
          method: 'tools/call',
          params: {
            'name' => 'calculate_sum',
            'arguments' => { 'a' => 5, 'b' => 3 }
          }
        )
        response = controller.handle_request(request)

        expect(response['error']).to be_nil
      end

      it 'treats missing arguments as empty object' do
        request = jsonrpc_request(
          method: 'tools/call',
          params: { 'name' => 'get_current_time' }
        )
        response = controller.handle_request(request)

        expect(response['error']).to be_nil
        expect(response['result']['content']).to be_an(Array)
      end
    end

    describe 'successful tool execution' do
      it 'returns result with content array' do
        request = jsonrpc_request(
          method: 'tools/call',
          params: {
            'name' => 'calculate_sum',
            'arguments' => { 'a' => 10, 'b' => 20 }
          }
        )
        response = controller.handle_request(request)

        expect(response['result']['content']).to be_an(Array)
      end

      it 'returns text content type for tool results' do
        request = jsonrpc_request(
          method: 'tools/call',
          params: {
            'name' => 'calculate_sum',
            'arguments' => { 'a' => 10, 'b' => 20 }
          }
        )
        response = controller.handle_request(request)

        content = response['result']['content'].first
        expect(content['type']).to eq('text')
        expect(content['text']).to be_a(String)
      end

      it 'executes the tool with provided arguments' do
        request = jsonrpc_request(
          method: 'tools/call',
          params: {
            'name' => 'calculate_sum',
            'arguments' => { 'a' => 7, 'b' => 8 }
          }
        )
        response = controller.handle_request(request)

        content = response['result']['content'].first
        result_data = JSON.parse(content['text'])
        expect(result_data['data']['result']).to eq(15)
      end

      it 'sets isError to false for successful execution' do
        request = jsonrpc_request(
          method: 'tools/call',
          params: {
            'name' => 'calculate_sum',
            'arguments' => { 'a' => 1, 'b' => 1 }
          }
        )
        response = controller.handle_request(request)

        expect(response['result']['isError']).to be false
      end
    end

    describe 'tool execution errors' do
      let(:controller_with_failing_tool) do
        tools = [failing_tool]
        klass = Class.new(ActiveIntelligence::MCP::BaseController) do
          @_mcp_tools = tools

          def self._mcp_tools
            @_mcp_tools
          end
        end
        ctrl = klass.new
        # Initialize it
        ctrl.handle_request(jsonrpc_request(
          method: 'initialize',
          params: {
            'protocolVersion' => '2025-11-25',
            'capabilities' => {},
            'clientInfo' => { 'name' => 'Test', 'version' => '1.0' }
          }
        ))
        ctrl.handle_request(jsonrpc_notification(method: 'notifications/initialized'))
        ctrl
      end

      it 'returns isError true for tool execution failures' do
        request = jsonrpc_request(
          method: 'tools/call',
          params: { 'name' => 'always_fails', 'arguments' => {} }
        )
        response = controller_with_failing_tool.handle_request(request)

        expect(response['result']['isError']).to be true
      end

      it 'includes error message in content for tool failures' do
        request = jsonrpc_request(
          method: 'tools/call',
          params: { 'name' => 'always_fails', 'arguments' => {} }
        )
        response = controller_with_failing_tool.handle_request(request)

        content = response['result']['content'].first
        expect(content['type']).to eq('text')
        expect(content['text']).to include('error')
      end
    end

    describe 'protocol errors' do
      it 'returns -32602 for unknown tool name' do
        request = jsonrpc_request(
          method: 'tools/call',
          params: {
            'name' => 'nonexistent_tool',
            'arguments' => {}
          }
        )
        response = controller.handle_request(request)

        expect(response['error']).not_to be_nil
        expect(response['error']['code']).to eq(-32602)
        expect(response['error']['message']).to match(/unknown tool/i)
      end

      it 'returns -32602 for invalid argument types' do
        request = jsonrpc_request(
          method: 'tools/call',
          params: {
            'name' => 'calculate_sum',
            'arguments' => { 'a' => 'not_a_number', 'b' => 5 }
          }
        )
        response = controller.handle_request(request)

        # This could be either a protocol error or a tool execution error
        # depending on implementation - both are valid per spec
        has_error = response['error'] || (response['result'] && response['result']['isError'])
        expect(has_error).to be_truthy
      end
    end
  end

  # ============================================================================
  # Section 6: Authentication Hooks
  # ============================================================================

  describe 'Authentication Hooks' do
    describe 'authenticate_mcp_request hook' do
      let(:authenticated_controller_class) do
        tools = [calculator_tool]
        Class.new(ActiveIntelligence::MCP::BaseController) do
          @_mcp_tools = tools
          @auth_token = 'secret-token'

          class << self
            attr_accessor :auth_token
          end

          def self._mcp_tools
            @_mcp_tools
          end

          protected

          def authenticate_mcp_request
            # Simulate checking authorization header
            auth_header = mcp_request_headers['Authorization']
            auth_header == "Bearer #{self.class.auth_token}"
          end
        end
      end

      let(:authenticated_controller) { authenticated_controller_class.new }

      it 'allows request when authentication succeeds' do
        authenticated_controller.set_request_headers('Authorization' => 'Bearer secret-token')

        # Initialize first
        init_request = jsonrpc_request(
          method: 'initialize',
          params: {
            'protocolVersion' => '2025-11-25',
            'capabilities' => {},
            'clientInfo' => { 'name' => 'Test', 'version' => '1.0' }
          }
        )
        authenticated_controller.handle_request(init_request)
        authenticated_controller.handle_request(
          jsonrpc_notification(method: 'notifications/initialized')
        )

        request = jsonrpc_request(method: 'tools/list')
        response = authenticated_controller.handle_request(request)

        expect(response['result']).to be_a(Hash)
        expect(response['error']).to be_nil
      end

      it 'rejects request when authentication fails' do
        authenticated_controller.set_request_headers('Authorization' => 'Bearer wrong-token')

        request = jsonrpc_request(method: 'initialize', params: {
          'protocolVersion' => '2025-11-25',
          'capabilities' => {},
          'clientInfo' => { 'name' => 'Test', 'version' => '1.0' }
        })
        response = authenticated_controller.handle_request(request)

        expect(response['error']).not_to be_nil
        expect(response['error']['code']).to eq(-32600) # or custom auth error code
      end

      it 'allows ping without authentication' do
        authenticated_controller.set_request_headers({}) # No auth header

        request = jsonrpc_request(method: 'ping')
        response = authenticated_controller.handle_request(request)

        # Ping should work without auth (health check)
        expect(response['result']).to eq({})
      end
    end

    describe 'before_tool_call hook' do
      let(:hook_tracking_controller_class) do
        tools = [calculator_tool]
        Class.new(ActiveIntelligence::MCP::BaseController) do
          @_mcp_tools = tools
          @before_calls = []

          class << self
            attr_accessor :before_calls
          end

          def self._mcp_tools
            @_mcp_tools
          end

          protected

          def before_tool_call(tool_name, params)
            self.class.before_calls << { tool: tool_name, params: params }
          end
        end
      end

      let(:hook_controller) do
        ctrl = hook_tracking_controller_class.new
        # Initialize
        ctrl.handle_request(jsonrpc_request(
          method: 'initialize',
          params: {
            'protocolVersion' => '2025-11-25',
            'capabilities' => {},
            'clientInfo' => { 'name' => 'Test', 'version' => '1.0' }
          }
        ))
        ctrl.handle_request(jsonrpc_notification(method: 'notifications/initialized'))
        ctrl
      end

      it 'calls before_tool_call hook with tool name and params' do
        hook_tracking_controller_class.before_calls.clear

        request = jsonrpc_request(
          method: 'tools/call',
          params: {
            'name' => 'calculate_sum',
            'arguments' => { 'a' => 1, 'b' => 2 }
          }
        )
        hook_controller.handle_request(request)

        expect(hook_tracking_controller_class.before_calls.length).to eq(1)
        expect(hook_tracking_controller_class.before_calls.first[:tool]).to eq('calculate_sum')
        expect(hook_tracking_controller_class.before_calls.first[:params]).to eq({ 'a' => 1, 'b' => 2 })
      end
    end

    describe 'after_tool_call hook' do
      let(:hook_tracking_controller_class) do
        tools = [calculator_tool]
        Class.new(ActiveIntelligence::MCP::BaseController) do
          @_mcp_tools = tools
          @after_calls = []

          class << self
            attr_accessor :after_calls
          end

          def self._mcp_tools
            @_mcp_tools
          end

          protected

          def after_tool_call(tool_name, params, result)
            self.class.after_calls << { tool: tool_name, params: params, result: result }
          end
        end
      end

      let(:hook_controller) do
        ctrl = hook_tracking_controller_class.new
        # Initialize
        ctrl.handle_request(jsonrpc_request(
          method: 'initialize',
          params: {
            'protocolVersion' => '2025-11-25',
            'capabilities' => {},
            'clientInfo' => { 'name' => 'Test', 'version' => '1.0' }
          }
        ))
        ctrl.handle_request(jsonrpc_notification(method: 'notifications/initialized'))
        ctrl
      end

      it 'calls after_tool_call hook with tool name, params, and result' do
        hook_tracking_controller_class.after_calls.clear

        request = jsonrpc_request(
          method: 'tools/call',
          params: {
            'name' => 'calculate_sum',
            'arguments' => { 'a' => 5, 'b' => 7 }
          }
        )
        hook_controller.handle_request(request)

        expect(hook_tracking_controller_class.after_calls.length).to eq(1)
        call = hook_tracking_controller_class.after_calls.first
        expect(call[:tool]).to eq('calculate_sum')
        expect(call[:params]).to eq({ 'a' => 5, 'b' => 7 })
        expect(call[:result][:success]).to be true
        expect(call[:result][:data][:result]).to eq(12)
      end
    end

    describe 'build_tool hook' do
      let(:dependency_injection_controller_class) do
        tools = [calculator_tool]
        Class.new(ActiveIntelligence::MCP::BaseController) do
          @_mcp_tools = tools
          @injected_context = nil

          class << self
            attr_accessor :injected_context
          end

          def self._mcp_tools
            @_mcp_tools
          end

          protected

          def build_tool(tool_class)
            tool = tool_class.new
            # Simulate dependency injection
            tool.instance_variable_set(:@context, { user_id: 123 })
            self.class.injected_context = { user_id: 123 }
            tool
          end
        end
      end

      let(:di_controller) do
        ctrl = dependency_injection_controller_class.new
        # Initialize
        ctrl.handle_request(jsonrpc_request(
          method: 'initialize',
          params: {
            'protocolVersion' => '2025-11-25',
            'capabilities' => {},
            'clientInfo' => { 'name' => 'Test', 'version' => '1.0' }
          }
        ))
        ctrl.handle_request(jsonrpc_notification(method: 'notifications/initialized'))
        ctrl
      end

      it 'uses build_tool to instantiate tools' do
        dependency_injection_controller_class.injected_context = nil

        request = jsonrpc_request(
          method: 'tools/call',
          params: {
            'name' => 'calculate_sum',
            'arguments' => { 'a' => 1, 'b' => 1 }
          }
        )
        di_controller.handle_request(request)

        expect(dependency_injection_controller_class.injected_context).to eq({ user_id: 123 })
      end
    end
  end

  # ============================================================================
  # Section 7: Error Codes Reference
  # Standard JSON-RPC 2.0 error codes
  # ============================================================================

  describe 'Standard JSON-RPC Error Codes' do
    # -32700: Parse error
    # -32600: Invalid Request
    # -32601: Method not found
    # -32602: Invalid params
    # -32603: Internal error

    it 'uses -32700 for parse errors' do
      response = controller.handle_raw_request('not valid json at all')

      expect(response['error']['code']).to eq(-32700)
    end

    it 'uses -32600 for invalid requests' do
      # Missing jsonrpc version
      response = controller.handle_request({ 'id' => 1, 'method' => 'ping' })

      expect(response['error']['code']).to eq(-32600)
    end

    it 'uses -32601 for method not found' do
      request = jsonrpc_request(method: 'completely_unknown_method')
      response = controller.handle_request(request)

      expect(response['error']['code']).to eq(-32601)
    end

    it 'uses -32602 for invalid params' do
      # Initialize first
      controller.handle_request(jsonrpc_request(
        method: 'initialize',
        params: {
          'protocolVersion' => '2025-11-25',
          'capabilities' => {},
          'clientInfo' => { 'name' => 'Test', 'version' => '1.0' }
        }
      ))
      controller.handle_request(jsonrpc_notification(method: 'notifications/initialized'))

      # tools/call without name
      request = jsonrpc_request(method: 'tools/call', params: {})
      response = controller.handle_request(request)

      expect(response['error']['code']).to eq(-32602)
    end

    it 'uses -32603 for internal errors' do
      # This would require triggering an unexpected exception
      # Implementation-specific test
    end
  end

  # ============================================================================
  # Section 8: Batch Requests (Optional JSON-RPC 2.0 feature)
  # ============================================================================

  describe 'Batch Requests (optional)' do
    it 'handles batch requests if supported' do
      batch = [
        jsonrpc_request(method: 'ping', id: 1),
        jsonrpc_request(method: 'ping', id: 2)
      ]

      response = controller.handle_batch_request(batch)

      if response # nil means not supported
        expect(response).to be_an(Array)
        expect(response.length).to eq(2)
        expect(response.map { |r| r['id'] }).to contain_exactly(1, 2)
      end
    end
  end
end
