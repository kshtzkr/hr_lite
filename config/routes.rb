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
  resources :salary_slips, only: %i[index show]
  resource :employee_profile, only: :show, path: "profile"
  resource :resignation, only: %i[show create], controller: "resignations" do
    post :withdraw
  end
  get "career", to: "career#show"
  resources :appraisals, only: %i[index show]

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
    resources :resignations, only: [] do
      member { post :accept }
    end
    resources :employees, except: :destroy do
      member { post :offboard }
      resources :salary_structures, only: %i[new create edit update]
      resources :appraisals, only: %i[new create edit update destroy] do
        member { post :share }
      end
      resources :designation_changes, only: %i[new create]
    end
    resources :payroll_runs, only: %i[index show new create destroy] do
      member do
        post :compute
        post :finalize
        post :unlock
        post :publish
        get :register
      end
    end
    resources :salary_slips, only: %i[show update]
    resource :setting, only: %i[edit update]
    resources :audit_logs, only: :index
  end
end
