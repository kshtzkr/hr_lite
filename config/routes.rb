HrLite::Engine.routes.draw do
  root "home#index"

  resources :kudos, only: %i[index create destroy]
  get "users/search", to: "users#search"

  namespace :admin do
    resources :audit_logs, only: :index
  end
end
