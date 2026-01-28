Rails.application.routes.draw do
  root "conversations#index"

  # ActionCable endpoint
  mount ActionCable.server => '/cable'

  # MCP (Model Context Protocol) endpoint
  # Allows AI applications to discover and use tools from this server
  post '/mcp', to: 'mcp#handle'

  resources :conversations, only: [:index, :create, :show] do
    member do
      post :send_message
      post :send_message_streaming
    end
  end
end
