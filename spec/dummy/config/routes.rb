Rails.application.routes.draw do
  mount HrLite::Engine => "/hr"

  # bin/demo persona picker (no-ops outside HR_LITE_DEMO=1).
  root "demo#index"
  post "demo/sign_in/:id", to: "demo#sign_in_as"

  # Test-only session endpoints (the dummy has no Devise; see
  # spec/support/auth_helpers.rb).
  post "test_session", to: "sessions#create"
  delete "test_session", to: "sessions#destroy"
end
