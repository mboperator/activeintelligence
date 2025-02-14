module AgentKit
  class ParameterSchema
    def self.define(&block)
      new.tap { |schema| schema.instance_eval(&block) }
    end

    def initialize
      @fields = {}
    end

    def string(name, required: true, enum: nil)
      @fields[name] = { type: :string, required: required, enum: enum }
    end

    def integer(name, required: true, min: nil, max: nil)
      @fields[name] = { type: :integer, required: required, min: min, max: max }
    end

    def validate!(params)
      @fields.each do |name, rules|
        value = params[name]

        if rules[:required] && value.nil?
          raise InvalidParametersError, "Missing required parameter: #{name}"
        end

        next if value.nil?

        case rules[:type]
        when :string
          unless value.is_a?(String)
            raise InvalidParametersError, "#{name} must be a string"
          end
          if rules[:enum] && !rules[:enum].include?(value)
            raise InvalidParametersError, "#{name} must be one of: #{rules[:enum].join(', ')}"
          end
        when :integer
          unless value.is_a?(Integer)
            raise InvalidParametersError, "#{name} must be an integer"
          end
          if rules[:min] && value < rules[:min]
            raise InvalidParametersError, "#{name} must be >= #{rules[:min]}"
          end
          if rules[:max] && value > rules[:max]
            raise InvalidParametersError, "#{name} must be <= #{rules[:max]}"
          end
        end
      end
    end
  end
end
