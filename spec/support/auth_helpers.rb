module AuthHelpers
  # The dummy app authenticates via a plain session key (no Devise). Request
  # specs sign in by hitting the test-only session endpoint.
  def sign_in(user)
    post "/test_session", params: { user_id: user.id }
  end

  def sign_out
    delete "/test_session"
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
