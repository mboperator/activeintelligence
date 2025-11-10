module ActiveIntelligence
  class Conversation < ActiveRecord::Base
    self.table_name = 'active_intelligence_conversations'

    has_many :messages, class_name: 'ActiveIntelligence::Message', dependent: :destroy

    validates :agent_class, presence: true
    validates :status, inclusion: { in: %w[active archived] }

    scope :active, -> { where(status: 'active') }
    scope :archived, -> { where(status: 'archived') }

    # Initialize an agent instance for this conversation
    def agent(options: {}, tools: nil)
      agent_class_constant = agent_class.constantize
      agent_class_constant.new(
        conversation: self,
        objective: objective,
        options: options,
        tools: tools
      )
    end

    # Archive this conversation
    def archive!
      update!(status: 'archived')
    end

    # Get the last message
    def last_message
      messages.order(created_at: :desc).first
    end

    # Get message count
    def message_count
      messages.count
    end
  end
end
