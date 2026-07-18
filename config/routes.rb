HrLite::Engine.routes.draw do
  root "home#index"

  resources :kudos, only: %i[index create destroy]
  get "users/search", to: "users#search"

  resource :attendance, only: :show, controller: "attendance" do
    post :check_in
    post :check_out
  end

  namespace :admin do
    resources :attendances, only: %i[index show update], param: :user_id
    resources :audit_logs, only: :index
  end
end
