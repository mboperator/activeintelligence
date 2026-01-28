# frozen_string_literal: true

require 'json'

module ActiveIntelligence
  module MCP
    # MCP Protocol Constants
    PROTOCOL_VERSION = '2025-11-25'
    SUPPORTED_VERSIONS = ['2025-11-25', '2024-11-05'].freeze

    # JSON-RPC 2.0 Error Codes
    module ErrorCodes
      PARSE_ERROR = -32700
      INVALID_REQUEST = -32600
      METHOD_NOT_FOUND = -32601
      INVALID_PARAMS = -32602
      INTERNAL_ERROR = -32603
    end

    # Base controller for MCP servers.
    #
    # Subclass this controller and use the DSL to register tools:
    #
    #   class McpController < ActiveIntelligence::MCP::BaseController
    #     mcp_tools MyTool, AnotherTool
    #
    #     protected
    #
    #     def authenticate_mcp_request
    #       # Custom authentication logic
    #       token = request_headers['Authorization']&.sub(/^Bearer /, '')
    #       @current_client = ApiClient.find_by(token: token)
    #       @current_client.present?
    #     end
    #   end
    #
    class BaseController
      class << self
        attr_accessor :_mcp_tools, :_server_name, :_server_version

        def _mcp_tools
          @_mcp_tools || []
        end

        def _server_name
          @_server_name || 'ActiveIntelligence MCP Server'
        end

        def _server_version
          @_server_version || '1.0.0'
        end

        # Ensure subclasses inherit parent's tools by default
        def inherited(subclass)
          subclass.instance_variable_set(:@_mcp_tools, @_mcp_tools&.dup || [])
          subclass.instance_variable_set(:@_server_name, @_server_name)
          subclass.instance_variable_set(:@_server_version, @_server_version)
        end

        # DSL method to register tools
        def mcp_tools(*tools)
          @_mcp_tools = tools
        end

        # DSL method to set server info
        def server_name(name)
          @_server_name = name
        end

        def server_version(version)
          @_server_version = version
        end
      end

      def initialize
        @initialized = false
        @session_ready = false
        @request_headers = {}
        @client_info = nil
        @client_capabilities = {}
      end

      # Check if the session has completed initialization
      def session_initialized?
        @session_ready
      end

      # Set request headers (for testing or manual header injection)
      def set_request_headers(headers)
        @request_headers = headers || {}
      end

      # Access request headers
      def request_headers
        @request_headers
      end

      # Handle raw JSON string input
      def handle_raw_request(json_string)
        begin
          request = JSON.parse(json_string)
        rescue JSON::ParserError => e
          return jsonrpc_error(nil, ErrorCodes::PARSE_ERROR, "Parse error: #{e.message}")
        end

        if request.is_a?(Array)
          handle_batch_request(request)
        else
          handle_request(request)
        end
      end

      # Handle batch requests (optional JSON-RPC 2.0 feature)
      def handle_batch_request(requests)
        return nil if requests.empty?

        responses = requests.map { |req| handle_request(req) }.compact
        responses.empty? ? nil : responses
      end

      # Main request handler
      def handle_request(request)
        # Validate basic JSON-RPC structure
        validation_error = validate_jsonrpc_request(request)
        return validation_error if validation_error

        method = request['method']
        id = request['id']
        params = request['params'] || {}

        # Check if this is a notification (no id)
        is_notification = !request.key?('id')

        # Route to appropriate handler
        result = route_request(method, params, id)

        # Don't send response for notifications
        return nil if is_notification

        result
      end

      protected

      # Override this method to implement custom authentication
      # Return true to allow the request, false to reject
      def authenticate_mcp_request
        true
      end

      # Override this method to customize tool instantiation
      def build_tool(tool_class)
        tool_class.new
      end

      # Hook called before tool execution
      def before_tool_call(tool_name, params)
        # Override in subclass
      end

      # Hook called after tool execution
      def after_tool_call(tool_name, params, result)
        # Override in subclass
      end

      # Override to customize server info
      def server_info
        {
          'name' => self.class._server_name,
          'version' => self.class._server_version
        }
      end

      # Override to provide custom instructions
      def server_instructions
        nil
      end

      private

      def validate_jsonrpc_request(request)
        return jsonrpc_error(nil, ErrorCodes::INVALID_REQUEST, 'Invalid Request: not a JSON object') unless request.is_a?(Hash)

        # Check jsonrpc version
        unless request['jsonrpc'] == '2.0'
          return jsonrpc_error(request['id'], ErrorCodes::INVALID_REQUEST, 'Invalid Request: missing or invalid jsonrpc version')
        end

        # Check for null id (MCP requirement: id MUST NOT be null)
        if request.key?('id') && request['id'].nil?
          return jsonrpc_error(nil, ErrorCodes::INVALID_REQUEST, 'Invalid Request: id must not be null')
        end

        # Check for method
        unless request['method'].is_a?(String)
          return jsonrpc_error(request['id'], ErrorCodes::INVALID_REQUEST, 'Invalid Request: missing or invalid method')
        end

        nil
      end

      def route_request(method, params, id)
        # Ping is always allowed (even before init, without auth)
        return handle_ping(id) if method == 'ping'

        # Initialize is allowed before session init but requires auth
        return handle_initialize(params, id) if method == 'initialize'

        # Initialized notification
        return handle_initialized_notification if method == 'notifications/initialized'

        # Check if the method is known before checking auth/lifecycle
        # This ensures we return METHOD_NOT_FOUND for unknown methods
        unless known_method?(method)
          return jsonrpc_error(id, ErrorCodes::METHOD_NOT_FOUND, "Method not found: #{method}")
        end

        # Check authentication for other methods
        unless authenticate_mcp_request
          return jsonrpc_error(id, ErrorCodes::INVALID_REQUEST, 'Authentication failed')
        end

        # Check lifecycle - most methods require initialization
        unless @initialized
          return jsonrpc_error(id, ErrorCodes::INVALID_REQUEST, 'Session not initialized. Send initialize request first.')
        end

        # Route to specific handlers
        case method
        when 'tools/list'
          handle_tools_list(params, id)
        when 'tools/call'
          handle_tools_call(params, id)
        else
          # Should not reach here due to known_method? check above
          jsonrpc_error(id, ErrorCodes::METHOD_NOT_FOUND, "Method not found: #{method}")
        end
      end

      def known_method?(method)
        %w[ping initialize notifications/initialized tools/list tools/call].include?(method)
      end

      # ========================================================================
      # Method Handlers
      # ========================================================================

      def handle_ping(id)
        jsonrpc_result(id, {})
      end

      def handle_initialize(params, id)
        # Check authentication
        unless authenticate_mcp_request
          return jsonrpc_error(id, ErrorCodes::INVALID_REQUEST, 'Authentication failed')
        end

        client_version = params['protocolVersion']
        @client_info = params['clientInfo']
        @client_capabilities = params['capabilities'] || {}

        # Version negotiation
        unless SUPPORTED_VERSIONS.include?(client_version)
          # Return our preferred version
          # Client can disconnect if they don't support it
        end

        @initialized = true

        response_version = SUPPORTED_VERSIONS.include?(client_version) ? client_version : PROTOCOL_VERSION

        result = {
          'protocolVersion' => response_version,
          'capabilities' => server_capabilities,
          'serverInfo' => server_info
        }

        instructions = server_instructions
        result['instructions'] = instructions if instructions

        jsonrpc_result(id, result)
      end

      def handle_initialized_notification
        @session_ready = true
        nil # Notifications don't get responses
      end

      def handle_tools_list(params, id)
        cursor = params['cursor']

        tools = registered_tools.map do |tool_class|
          tool_to_mcp_schema(tool_class)
        end

        result = { 'tools' => tools }
        # Add nextCursor if implementing pagination
        # result['nextCursor'] = next_cursor if next_cursor

        jsonrpc_result(id, result)
      end

      def handle_tools_call(params, id)
        tool_name = params['name']
        arguments = params['arguments'] || {}

        # Validate required params
        unless tool_name
          return jsonrpc_error(id, ErrorCodes::INVALID_PARAMS, 'Invalid params: missing required parameter "name"')
        end

        # Find the tool
        tool_class = find_tool_by_name(tool_name)
        unless tool_class
          return jsonrpc_error(id, ErrorCodes::INVALID_PARAMS, "Unknown tool: #{tool_name}")
        end

        # Execute the tool
        begin
          before_tool_call(tool_name, arguments)

          tool = build_tool(tool_class)
          result = tool.call(arguments)

          after_tool_call(tool_name, arguments, result)

          # Format response according to MCP spec
          format_tool_result(id, result)
        rescue InvalidParameterError => e
          # Tool parameter validation error - return as tool execution error
          format_tool_error(id, e.message)
        rescue StandardError => e
          # Unexpected error
          jsonrpc_error(id, ErrorCodes::INTERNAL_ERROR, "Internal error: #{e.message}")
        end
      end

      # ========================================================================
      # Helper Methods
      # ========================================================================

      def server_capabilities
        capabilities = {}

        if registered_tools.any?
          capabilities['tools'] = {
            'listChanged' => false # We don't support dynamic tool changes yet
          }
        end

        capabilities
      end

      def registered_tools
        self.class._mcp_tools || []
      end

      def find_tool_by_name(name)
        registered_tools.find { |t| t.name == name }
      end

      def tool_to_mcp_schema(tool_class)
        schema = tool_class.to_json_schema

        # Convert to MCP format
        mcp_schema = {
          'name' => schema[:name],
          'description' => schema[:description] || '',
          'inputSchema' => convert_input_schema(schema[:input_schema], tool_class)
        }

        mcp_schema
      end

      def convert_input_schema(schema, tool_class)
        return { 'type' => 'object', 'additionalProperties' => false } unless schema

        result = {
          'type' => 'object',
          'properties' => {}
        }

        if schema[:properties]
          schema[:properties].each do |name, prop|
            result['properties'][name.to_s] = {
              'type' => prop[:type],
              'description' => prop[:description]
            }.compact
          end
        end

        # Add required fields
        required = tool_class.parameters.select { |_, opts| opts[:required] }.keys.map(&:to_s)
        result['required'] = required if required.any?

        result
      end

      def format_tool_result(id, result)
        if result[:error]
          # Tool returned an error response
          jsonrpc_result(id, {
            'content' => [
              {
                'type' => 'text',
                'text' => JSON.generate(result)
              }
            ],
            'isError' => true
          })
        else
          # Tool returned success
          jsonrpc_result(id, {
            'content' => [
              {
                'type' => 'text',
                'text' => JSON.generate(result)
              }
            ],
            'isError' => false
          })
        end
      end

      def format_tool_error(id, message)
        jsonrpc_result(id, {
          'content' => [
            {
              'type' => 'text',
              'text' => JSON.generate({ error: true, message: message })
            }
          ],
          'isError' => true
        })
      end

      # ========================================================================
      # JSON-RPC Response Helpers
      # ========================================================================

      def jsonrpc_result(id, result)
        {
          'jsonrpc' => '2.0',
          'id' => id,
          'result' => result
        }
      end

      def jsonrpc_error(id, code, message, data = nil)
        error = {
          'code' => code,
          'message' => message
        }
        error['data'] = data if data

        {
          'jsonrpc' => '2.0',
          'id' => id,
          'error' => error
        }
      end
    end
  end
end
