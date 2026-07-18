HrLite::Engine.routes.draw do
  root "home#index"

  resources :kudos, only: %i[index create destroy]
  get "users/search", to: "users#search"

  resource :attendance, only: :show, controller: "attendance" do
    post :check_in
    post :check_out
  end

  resources :leave_requests, only: %i[index show new create] do
    member { post :cancel }
  end
  resources :leave_balances, only: :index
  resources :holidays, only: :index
  get "calendar", to: "calendar#show"

  namespace :admin do
    get "overview", to: "overview#index"
    resources :attendances, only: %i[index show update], param: :user_id
    resources :leave_requests, only: %i[index show] do
      member { post :approve; post :reject }
    end
    resources :leave_balances, only: :index do
      collection { post :adjust }
    end
    resources :leave_types, except: :show
    resources :office_locations, except: :show
    resources :holidays, only: %i[index create update destroy] do
      collection { post :bulk_create }
    end
    resource :setting, only: %i[edit update]
    resources :audit_logs, only: :index
  end
end
