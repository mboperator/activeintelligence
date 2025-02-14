module AgentKit
  class Tool
    class << self
      def schema(&block)
        @parameter_schema = ParameterSchema.define(&block)
      end

      def parameter_schema
        @parameter_schema
      end
      def parameters
        raise NotImplementedError, "#{self.name} must implement .parameters"
      end

      def name
        self.to_s.split('::').last
      end

      def description
        "#{name} - Add a description by setting self.description in your subclass"
      end
    end

    def execute(params)
      validate_parameters!(params)
      start_time = Time.now

      begin
        result = execute_with_logging(params)
        duration = Time.now - start_time
        Logger.instance.log_tool_execution(self.class.name, params, result, duration)
        result
      rescue StandardError => e
        Logger.instance.log_error(e, { tool: self.class.name, params: params })
        raise ToolExecutionError, "#{self.class.name} execution failed: #{e.message}"
      end
    end

    private

    def execute_with_logging(params)
      raise NotImplementedError, "#{self.class.name} must implement #execute_with_logging"
    end

    def validate_parameters!(params)
      return unless self.class.parameter_schema
      self.class.parameter_schema.validate!(params)
    end
  end
end
