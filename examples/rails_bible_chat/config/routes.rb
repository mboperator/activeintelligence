Rails.application.routes.draw do
  root "conversations#index"

  # ActionCable endpoint
  mount ActionCable.server => '/cable'

  resources :conversations, only: [:index, :create, :show] do
    member do
      post :send_message
      post :send_message_streaming
    end
  end
end
