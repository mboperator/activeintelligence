# lib/active_intelligence/tool.rb
module ActiveIntelligence
  class Tool
    # Class-level attributes and methods
    class << self
      attr_reader :parameters, :error_handlers, :rescue_handlers, :context_fields

      def inherited(subclass)
        subclass.instance_variable_set(:@parameters, {})
        subclass.instance_variable_set(:@error_handlers, {})
        subclass.instance_variable_set(:@rescue_handlers, {})
        subclass.instance_variable_set(:@tool_type, :query)
        subclass.instance_variable_set(:@tool_description, nil)
        subclass.instance_variable_set(:@execution_context, :backend)

        # Inherit context fields from parent class
        parent_context_fields = subclass.superclass.respond_to?(:context_fields) ?
          subclass.superclass.context_fields&.dup || {} : {}
        subclass.instance_variable_set(:@context_fields, parent_context_fields)

        if subclass.name
          subclass.instance_variable_set(:@tool_name, underscore(subclass.name.split('::').last))
        else
          subclass.instance_variable_set(:@tool_name, "tool_#{object_id}")
        end
      end
      
      # Simple underscore method (similar to ActiveSupport's)
      def underscore(camel_cased_word)
        return camel_cased_word unless camel_cased_word =~ /[A-Z-]|::/
        word = camel_cased_word.to_s.gsub('::', '/')
        word.gsub!(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
        word.gsub!(/([a-z\d])([A-Z])/, '\1_\2')
        word.tr!("-", "_")
        word.downcase!
        word
      end
      
      def tool_type(type = nil)
        @tool_type = type if type
        @tool_type
      end

      def description(desc = nil)
        @tool_description = desc if desc
        @tool_description
      end

      def name(custom_name = nil)
        if custom_name
          @tool_name = custom_name
        else
          @tool_name
        end
      end

      # Execution context DSL - where this tool runs (:backend or :frontend)
      def execution_context(context = nil)
        @execution_context = context if context
        @execution_context
      end

      # Helper method to check if this tool runs on the frontend
      def frontend?
        @execution_context == :frontend
      end

      # Helper method to check if this tool runs on the backend
      def backend?
        @execution_context == :backend
      end
      
      def param(name, type: String, required: false, description: nil, default: nil, enum: nil)
        @parameters[name] = {
          type: type,
          required: required,
          description: description,
          default: default,
          enum: enum
        }
      end

      # Context field DSL - declares expected context from the Agent
      # Context is runtime data (current_user, current_school) separate from LLM params
      def context_field(name, required: false, type: nil)
        @context_fields ||= {}
        @context_fields[name] = {
          required: required,
          type: type
        }

        # Generate accessor method for this context field
        define_method(name) do
          @context[name]
        end
      end
      
      # Define error handlers for specific scenarios
      def on_error(error_type, &block)
        @error_handlers[error_type] = block
      end
      
      # Rescue specific exceptions and convert to tool errors
      def rescue_from(exception_class, with: nil, &block)
        handler = block_given? ? block : with
        @rescue_handlers[exception_class] = handler
      end
      
      # Generate JSON schema for LLM tool calling APIs
      def to_json_schema
        properties = {}
        required = []
        
        @parameters.each do |name, options|
          properties[name] = {
            type: ruby_type_to_json_type(options[:type]),
            description: options[:description]
          }
          
          properties[name][:enum] = options[:enum] if options[:enum]
          required << name.to_s if options[:required]
        end
        
        {
          name: name,
          description: @tool_description,
          input_schema: {
            type: "object",
            properties: properties,
          }
        }
      end
      
      def ruby_type_to_json_type(type)
        case type.to_s
        when "String" then "string"
        when "Integer" then "integer"
        when "Float" then "number"
        when "TrueClass", "FalseClass", "Boolean" then "boolean"
        when "Array" then "array"
        when "Hash" then "object"
        else "string" # Default to string
        end
      end
      
      # Is this a query tool? (returns data without side effects)
      def query?
        @tool_type == :query
      end
      
      # Is this a command tool? (has side effects)
      def command?
        @tool_type == :command
      end
    end
    
    # Instance methods
    attr_reader :context

    def initialize(context: {})
      @context = context.dup.freeze
      validate_context! if self.class.context_fields&.any?
    end

    def call(params = {})
      # Convert string keys to symbols
      params = symbolize_keys(params)
      
      # Apply default values
      params = apply_defaults(params)
      
      # Validate parameters
      validate_params!(params)
      
      # Execute the tool with error handling
      begin
        execute(params)
      rescue StandardError => e
        handle_exception(e, params)
      end
    end
    
    # To be implemented by subclasses
    def execute(params)
      raise NotImplementedError, "Subclasses must implement #execute"
    end
    
    protected
    
    def symbolize_keys(hash)
      hash.transform_keys(&:to_sym)
    end
    
    def apply_defaults(params)
      result = params.dup
      
      self.class.parameters.each do |name, options|
        if !result.key?(name) && options.key?(:default)
          result[name] = options[:default]
        end
      end
      
      result
    end
    
    def validate_params!(params)
      self.class.parameters.each do |name, options|
        # Check required parameters
        if options[:required] && !params.key?(name)
          raise InvalidParameterError.new(
            "Missing required parameter: #{name}",
            details: { parameter: name }
          )
        end

        # Skip validation for nil values (unless required)
        next if !params.key?(name) || params[name].nil?

        # Type checking
        if options[:type] && !params[name].is_a?(options[:type])
          raise InvalidParameterError.new(
            "Invalid type for parameter #{name}: expected #{options[:type]}, got #{params[name].class}",
            details: { parameter: name, expected: options[:type].to_s, received: params[name].class.to_s }
          )
        end

        # Enum validation
        if options[:enum] && !options[:enum].include?(params[name])
          raise InvalidParameterError.new(
            "Invalid value for parameter #{name}: must be one of #{options[:enum].join(', ')}",
            details: { parameter: name, allowed_values: options[:enum], received: params[name] }
          )
        end
      end
    end

    def validate_context!
      missing_fields = []

      self.class.context_fields.each do |name, options|
        if options[:required] && (!@context.key?(name) || @context[name].nil?)
          missing_fields << name
        end
      end

      return if missing_fields.empty?

      raise ContextError.new(
        "Missing required context: #{missing_fields.join(', ')}",
        missing_fields: missing_fields
      )
    end
    
    def handle_exception(exception, params)
      # Check if we have a specific rescue handler for this exception class
      handler = find_rescue_handler(exception.class)
      
      if handler
        if handler.is_a?(Symbol)
          send(handler, exception, params)
        else
          instance_exec(exception, params, &handler)
        end
      elsif exception.is_a?(ToolError)
        # It's already a ToolError, so return its response format
        exception.to_response
      else
        # Convert generic exceptions to ToolError
        ToolError.new(
          "Tool execution failed: #{exception.message}",
          details: { 
            exception_class: exception.class.to_s,
            backtrace: exception.backtrace&.first(3)
          }
        ).to_response
      end
    end
    
    def find_rescue_handler(exception_class)
      # Find the most specific handler for this exception
      self.class.rescue_handlers.find do |klass, handler|
        exception_class <= klass
      end&.last
    end
    
    def handle_error(error_type, params)
      handler = self.class.error_handlers[error_type]
      instance_exec(params, &handler) if handler
    end
    
    # Helper for creating error responses
    def error_response(message, details = {})
      {
        error: true,
        message: message,
        details: details
      }
    end
    
    # Helper for creating success responses
    def success_response(data)
      {
        success: true,
        data: data
      }
    end
  end
  
  # Convenience subclasses
  class QueryTool < Tool
    tool_type :query
  end
  
  class CommandTool < Tool
    tool_type :command
  end
end