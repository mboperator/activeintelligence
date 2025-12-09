module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :conversation_id

    def connect
      self.conversation_id = request.params[:conversation_id]
    end
  end
end
