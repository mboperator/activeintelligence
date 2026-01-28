# frozen_string_literal: true

require 'json'

module ActiveIntelligence
  module MCP
    # Rails controller module for MCP servers.
    #
    # Include this module in a Rails controller to create an MCP endpoint:
    #
    #   class McpController < ApplicationController
    #     include ActiveIntelligence::MCP::RailsController
    #
    #     mcp_tools BibleReferenceTool, CalculatorTool
    #
    #     # Optional: customize server info
    #     mcp_server_name 'My App MCP Server'
    #     mcp_server_version '1.0.0'
    #
    #     protected
    #
    #     def authenticate_mcp_request
    #       # Custom authentication using Rails request
    #       token = request.headers['Authorization']&.sub(/^Bearer /, '')
    #       @current_client = ApiClient.find_by(token: token)
    #       @current_client.present?
    #     end
    #   end
    #
    # Then in routes.rb:
    #
    #   post '/mcp', to: 'mcp#handle'
    #   # Or for full MCP endpoint with SSE support:
    #   match '/mcp', to: 'mcp#handle', via: [:get, :post]
    #
    module RailsController
      extend ActiveSupport::Concern

      included do
        # Skip CSRF for API endpoints
        skip_before_action :verify_authenticity_token, raise: false

        # Class-level configuration
        class_attribute :_mcp_tools, default: []
        class_attribute :_mcp_server_name, default: 'ActiveIntelligence MCP Server'
        class_attribute :_mcp_server_version, default: '1.0.0'
      end

      class_methods do
        def mcp_tools(*tools)
          self._mcp_tools = tools
        end

        def mcp_server_name(name)
          self._mcp_server_name = name
        end

        def mcp_server_version(version)
          self._mcp_server_version = version
        end
      end

      # Main MCP endpoint handler
      def handle
        # Get or create the MCP handler for this session
        handler = mcp_handler

        # Inject Rails request headers
        handler.set_request_headers(request.headers.to_h)

        # Parse and handle the request
        body = request.body.read

        if body.blank?
          render json: jsonrpc_error(nil, ErrorCodes::INVALID_REQUEST, 'Empty request body')
          return
        end

        response_data = handler.handle_raw_request(body)

        if response_data.nil?
          # Notification - no response needed
          head :no_content
        else
          render json: response_data
        end
      rescue JSON::ParserError => e
        render json: jsonrpc_error(nil, ErrorCodes::PARSE_ERROR, "Parse error: #{e.message}")
      rescue StandardError => e
        Rails.logger.error "MCP Error: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: jsonrpc_error(nil, ErrorCodes::INTERNAL_ERROR, "Internal error: #{e.message}")
      end

      protected

      # Override this method to implement custom authentication
      # Has access to full Rails request object
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
          'name' => self.class._mcp_server_name,
          'version' => self.class._mcp_server_version
        }
      end

      # Override to provide custom instructions
      def server_instructions
        nil
      end

      private

      # Get or create MCP handler for the current session
      # Uses session to maintain state across requests
      def mcp_handler
        # Create a new handler for each request but restore session state
        handler = McpHandler.new(
          tools: self.class._mcp_tools,
          controller: self
        )

        # Restore session state if available
        if session[:mcp_initialized]
          handler.restore_session(
            initialized: session[:mcp_initialized],
            session_ready: session[:mcp_session_ready],
            client_info: session[:mcp_client_info],
            client_capabilities: session[:mcp_client_capabilities]
          )
        end

        handler
      end

      def jsonrpc_error(id, code, message)
        {
          'jsonrpc' => '2.0',
          'id' => id,
          'error' => {
            'code' => code,
            'message' => message
          }
        }
      end

      # Internal handler class that wraps the base MCP logic
      class McpHandler < BaseController
        attr_reader :controller

        def initialize(tools:, controller:)
          super()
          @controller = controller
          self.class._mcp_tools = tools
        end

        def restore_session(initialized:, session_ready:, client_info:, client_capabilities:)
          @initialized = initialized
          @session_ready = session_ready
          @client_info = client_info
          @client_capabilities = client_capabilities || {}
        end

        def save_session_to(session)
          session[:mcp_initialized] = @initialized
          session[:mcp_session_ready] = @session_ready
          session[:mcp_client_info] = @client_info
          session[:mcp_client_capabilities] = @client_capabilities
        end

        protected

        def authenticate_mcp_request
          @controller.send(:authenticate_mcp_request)
        end

        def build_tool(tool_class)
          @controller.send(:build_tool, tool_class)
        end

        def before_tool_call(tool_name, params)
          @controller.send(:before_tool_call, tool_name, params)
        end

        def after_tool_call(tool_name, params, result)
          @controller.send(:after_tool_call, tool_name, params, result)
        end

        def server_info
          @controller.send(:server_info)
        end

        def server_instructions
          @controller.send(:server_instructions)
        end

        # Override to save session after handling
        def handle_initialize(params, id)
          result = super
          save_session_to(@controller.session)
          result
        end

        def handle_initialized_notification
          result = super
          save_session_to(@controller.session)
          result
        end
      end
    end
  end
end
