Rails.application.routes.draw do
  mount HrLite::Engine => "/hr"

  # Test-only session endpoints (the dummy has no Devise; see
  # spec/support/auth_helpers.rb).
  post "test_session", to: "sessions#create"
  delete "test_session", to: "sessions#destroy"
end
