Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  devise_for :users

  resources :races, only: %i[index new create show destroy] do
    member do
      patch :start_finish
    end
  end

  # Defines the root path route ("/")
  root "races#index"
end
