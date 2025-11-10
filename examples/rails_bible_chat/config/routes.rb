Rails.application.routes.draw do
  root "conversations#index"

  resources :conversations, only: [:index, :create, :show] do
    member do
      post :send_message
      post :send_message_streaming
    end
  end
end
