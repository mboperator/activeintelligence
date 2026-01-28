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
    # Subclass this controller in your Rails app to create an MCP endpoint:
    #
    #   class McpController < ActiveIntelligence::MCP::BaseController
    #     mcp_tools MyTool, AnotherTool
    #
    #     # Optional: customize server info
    #     mcp_server_name 'My App MCP Server'
    #     mcp_server_version '1.0.0'
    #
    #     protected
    #
    #     def authenticate_mcp_request
    #       # Custom authentication - has access to request, session, etc.
    #       token = request.headers['Authorization']&.sub(/^Bearer /, '')
    #       @current_client = ApiClient.find_by(token: token)
    #       @current_client.present?
    #     end
    #
    #     def build_tool(tool_class)
    #       # Dependency injection
    #       tool_class.new(user: @current_client.user)
    #     end
    #   end
    #
    # Then in routes.rb:
    #
    #   post '/mcp', to: 'mcp#handle'
    #
    class BaseController < ActionController::API
      class << self
        attr_accessor :_mcp_tools, :_mcp_server_name, :_mcp_server_version

        def _mcp_tools
          @_mcp_tools || []
        end

        def _mcp_server_name
          @_mcp_server_name || 'ActiveIntelligence MCP Server'
        end

        def _mcp_server_version
          @_mcp_server_version || '1.0.0'
        end

        # Ensure subclasses inherit parent's configuration
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@_mcp_tools, @_mcp_tools&.dup || [])
          subclass.instance_variable_set(:@_mcp_server_name, @_mcp_server_name)
          subclass.instance_variable_set(:@_mcp_server_version, @_mcp_server_version)
        end

        # DSL method to register tools
        def mcp_tools(*tools)
          @_mcp_tools = tools
        end

        # DSL methods for server info
        def mcp_server_name(name)
          @_mcp_server_name = name
        end

        def mcp_server_version(version)
          @_mcp_server_version = version
        end
      end

      # Main MCP endpoint action - wire this to POST /mcp in routes
      def handle
        body = request.body.read

        if body.blank?
          render json: jsonrpc_error(nil, ErrorCodes::INVALID_REQUEST, 'Empty request body')
          return
        end

        # Store request headers for use in authenticate_mcp_request
        @_request_headers = request.headers.to_h

        # Restore MCP session state
        restore_mcp_session

        response_data = handle_raw_request(body)

        # Save MCP session state
        save_mcp_session

        if response_data.nil?
          # Notification - no response needed
          head :no_content
        else
          render json: response_data
        end
      rescue JSON::ParserError => e
        render json: jsonrpc_error(nil, ErrorCodes::PARSE_ERROR, "Parse error: #{e.message}")
      rescue StandardError => e
        Rails.logger.error "MCP Error: #{e.message}\n#{e.backtrace.join("\n")}" if defined?(Rails)
        render json: jsonrpc_error(nil, ErrorCodes::INTERNAL_ERROR, "Internal error: #{e.message}")
      end

      # Handle raw JSON string input (used by handle action and tests)
      def handle_raw_request(json_string)
        begin
          request_data = JSON.parse(json_string)
        rescue JSON::ParserError => e
          return jsonrpc_error(nil, ErrorCodes::PARSE_ERROR, "Parse error: #{e.message}")
        end

        if request_data.is_a?(Array)
          handle_batch_request(request_data)
        else
          handle_jsonrpc_request(request_data)
        end
      end

      # Handle batch requests (optional JSON-RPC 2.0 feature)
      def handle_batch_request(requests)
        return nil if requests.empty?

        responses = requests.map { |req| handle_jsonrpc_request(req) }.compact
        responses.empty? ? nil : responses
      end

      # Main JSON-RPC request handler (aliased for backward compatibility)
      def handle_jsonrpc_request(request_data)
        handle_request(request_data)
      end

      def handle_request(request_data)
        # Validate basic JSON-RPC structure
        validation_error = validate_jsonrpc_request(request_data)
        return validation_error if validation_error

        method = request_data['method']
        id = request_data['id']
        params = request_data['params'] || {}

        # Check if this is a notification (no id)
        is_notification = !request_data.key?('id')

        # Route to appropriate handler
        result = route_request(method, params, id)

        # Don't send response for notifications
        return nil if is_notification

        result
      end

      # Check if the MCP session has completed initialization
      def session_initialized?
        @_mcp_session_ready
      end

      # For testing: allow setting request headers directly
      def set_request_headers(headers)
        @_request_headers = headers || {}
      end

      # Access request headers (from Rails request or set manually for tests)
      def mcp_request_headers
        @_request_headers || {}
      end

      protected

      # Override this method to implement custom authentication
      # Has full access to Rails request, session, etc.
      # Return true to allow the request, false to reject
      def authenticate_mcp_request
        true
      end

      # Override this method to customize tool instantiation (dependency injection)
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
          'name' => self.class._mcp_server_name,
          'version' => self.class._mcp_server_version
        }
      end

      # Override to provide custom instructions shown to AI clients
      def server_instructions
        nil
      end

      private

      # Session management for MCP state
      def restore_mcp_session
        return unless defined?(session) && session

        @_mcp_initialized = session[:mcp_initialized] || false
        @_mcp_session_ready = session[:mcp_session_ready] || false
        @_mcp_client_info = session[:mcp_client_info]
        @_mcp_client_capabilities = session[:mcp_client_capabilities] || {}
      end

      def save_mcp_session
        return unless defined?(session) && session

        session[:mcp_initialized] = @_mcp_initialized
        session[:mcp_session_ready] = @_mcp_session_ready
        session[:mcp_client_info] = @_mcp_client_info
        session[:mcp_client_capabilities] = @_mcp_client_capabilities
      end

      def validate_jsonrpc_request(request_data)
        return jsonrpc_error(nil, ErrorCodes::INVALID_REQUEST, 'Invalid Request: not a JSON object') unless request_data.is_a?(Hash)

        # Check jsonrpc version
        unless request_data['jsonrpc'] == '2.0'
          return jsonrpc_error(request_data['id'], ErrorCodes::INVALID_REQUEST, 'Invalid Request: missing or invalid jsonrpc version')
        end

        # Check for null id (MCP requirement: id MUST NOT be null)
        if request_data.key?('id') && request_data['id'].nil?
          return jsonrpc_error(nil, ErrorCodes::INVALID_REQUEST, 'Invalid Request: id must not be null')
        end

        # Check for method
        unless request_data['method'].is_a?(String)
          return jsonrpc_error(request_data['id'], ErrorCodes::INVALID_REQUEST, 'Invalid Request: missing or invalid method')
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
        unless @_mcp_initialized
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
        @_mcp_client_info = params['clientInfo']
        @_mcp_client_capabilities = params['capabilities'] || {}

        @_mcp_initialized = true

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
        @_mcp_session_ready = true
        nil # Notifications don't get responses
      end

      def handle_tools_list(_params, id)
        tools = registered_tools.map do |tool_class|
          tool_to_mcp_schema(tool_class)
        end

        result = { 'tools' => tools }
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

        {
          'name' => schema[:name],
          'description' => schema[:description] || '',
          'inputSchema' => convert_input_schema(schema[:input_schema], tool_class)
        }
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
          jsonrpc_result(id, {
            'content' => [{ 'type' => 'text', 'text' => JSON.generate(result) }],
            'isError' => true
          })
        else
          jsonrpc_result(id, {
            'content' => [{ 'type' => 'text', 'text' => JSON.generate(result) }],
            'isError' => false
          })
        end
      end

      def format_tool_error(id, message)
        jsonrpc_result(id, {
          'content' => [{ 'type' => 'text', 'text' => JSON.generate({ error: true, message: message }) }],
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
        error = { 'code' => code, 'message' => message }
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
