HrLite::Engine.routes.draw do
  root "home#index"

  resources :kudos, only: %i[index create destroy]
  get "users/search", to: "users#search"

  resource :attendance, only: :show, controller: "attendance" do
    post :check_in
    post :check_out
    post :slot
  end

  resources :leave_requests, only: %i[index show new create] do
    member { post :cancel }
  end
  resources :leave_balances, only: :index
  resources :comp_off_requests, only: %i[index new create] do
    member { post :cancel }
  end
  resources :regularization_requests, only: %i[index new create] do
    member { post :cancel }
  end
  resources :wfh_requests, only: %i[index create] do
    member { post :cancel }
  end
  get "work_time", to: "work_time#show", as: :work_time
  resource :work_mode, only: :create do
    post :end_overlay
    get :crm_search
    post :status
    post :clear_status
  end
  resources :work_locations, only: %i[index create] do
    member { post :activate; post :remove }
  end
  resources :approvals, only: :index
  resources :expenses, only: %i[index new create] do
    member { post :cancel }
  end
  resources :hr_requests, only: %i[index show new create] do
    member { post :cancel }
  end
  resources :policies, only: %i[index show] do
    member { post :acknowledge }
  end
  resources :benefits, only: :index
  resources :documents, only: %i[index create destroy] do
    member { get :download }
  end
  resource :tax_declaration, only: %i[show update], controller: "tax_declarations" do
    post :submit
    post :preview
  end
  resources :loans, only: :index
  get "team", to: "team#show"
  get "org", to: "org#show"
  get "timeline", to: "timelines#show"
  get "people/:user_id/timeline", to: "timelines#show", as: :person_timeline
  resources :holidays, only: :index
  get "calendar", to: "calendar#show"
  get "search", to: "search#show", as: :search
  resources :salary_slips, only: %i[index show]
  resource :employee_profile, only: :show, path: "profile"
  patch "id_card/photo", to: "id_cards#photo", as: :id_card_photo
  get "id_card(/:user_id)", to: "id_cards#show", as: :id_card
  resource :resignation, only: %i[show create], controller: "resignations" do
    post :withdraw
  end
  get "career", to: "career#show"
  resources :appraisals, only: %i[index show]

  namespace :admin do
    resources :policies, only: %i[index new create]
    resources :hiring_campaigns, except: %i[destroy] do
      member { get :import; post :import }
      resources :hiring_sends, path: "send", only: %i[new create]
    end
    resources :hiring_candidates, only: %i[show] do
      member { patch :stage }
      resources :hiring_interviews, path: "interviews", only: %i[create update destroy]
    end
    resources :hiring_templates, except: %i[show destroy]
    post "hiring_messages/:id/retry", to: "hiring_sends#retry", as: :retry_hiring_message
    get "overview", to: "overview#index"
    resources :attendances, only: %i[index show update], param: :user_id do
      collection { get :week }
      member { get :summary; patch :shorter_day; post :slot; post :unlock_slot; post :remove_penalty; post :remove_penalty_hours }
    end
    resources :leave_requests, only: %i[index show new create edit update] do
      member { post :approve; post :reject; post :cancel }
    end
    resources :leave_balances, only: :index do
      collection { post :adjust }
    end
    resources :comp_off_requests, only: %i[index show] do
      member { post :approve; post :reject }
    end
    resources :regularization_requests, only: %i[index show] do
      member { post :approve; post :reject }
    end
    resources :wfh_requests, only: %i[index show create update] do
      member { post :approve; post :reject }
    end
    resources :work_locations, only: :index do
      member { post :approve; post :reject; post :remove }
    end
    get "work_modes", to: "work_modes#index", as: :work_modes
    get "work_time", to: "work_time#index", as: :work_time
    post "work_modes/:user_id", to: "work_modes#override", as: :work_mode_override
    resources :roles, except: :show do
      resources :assignments, only: %i[create destroy], controller: "role_assignments"
    end
    resources :statutory_rate_cards, only: %i[index new create edit update]
    resources :documents, only: :index do
      member { post :verify; post :reject }
    end
    get "documents/for/:user_id", to: "documents#show", as: :employee_documents
    post "documents/for/:user_id", to: "documents#create"
    resources :tax_declarations, only: %i[index show update] do
      member { post :verify; post :reject; post :accept_all; get "proofs/:proof_id", action: :proof, as: :proof }
      collection { get :overview; get "people/:user_id", action: :person, as: :person }
    end
    resources :loans, only: %i[index new create show] do
      member { post :close; post :cancel }
    end
    resources :reports, only: %i[index show]
    resources :expenses, only: :index do
      member { post :approve; post :reject; post :reimburse; get :receipt }
    end
    resources :hr_requests, only: %i[index show] do
      member { post :assign; post :resolve }
    end
    resources :assets, only: %i[index new create] do
      member { post :assign; post :take_back }
    end
    resources :benefits, only: %i[index new create] do
      member { post :enrol; post :unenrol }
    end
    resources :checklists, only: :index do
      member { post :complete; post :reopen }
    end
    resources :leave_types, except: :show
    resources :office_locations, except: :show
    resources :expense_categories, except: %i[show destroy]
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
    resources :performance_plans, only: %i[index new create edit update]
    resources :awards, only: %i[index new create edit update]
    resources :ca_reviews, only: :index do
      collection { post :verify; post :flag; post :verify_all }
      member { post :resolve }
    end
    resources :payroll_runs, only: %i[index show new create destroy] do
      member do
        post :compute
        post :approve
        post :unlock
        post :publish
        get :register
      end
    end
    resources :payroll_line_items, only: %i[index new create destroy]
    resources :salary_slips, only: %i[show update]
    resource :setting, only: %i[edit update]
    resources :audit_logs, only: :index
  end
end
