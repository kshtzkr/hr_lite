require "rails_helper"

# The whole suite runs with forgery protection off (spec/dummy/config/application.rb),
# which is why three dead "Reject" buttons shipped: a request spec can post any
# params it likes without ever exercising a real token.
#
# These examples turn protection back ON, render the decision screen, pull the
# token out of the markup the admin's browser would submit, and post THAT. With
# `per_form_csrf_tokens` (the Rails 8 default, and what the host app runs) a
# token is bound to its form's action — so a form retargeted with `formaction:`
# fails here exactly as it failed in production with a 422.
RSpec.describe "Admin decision forms carry a usable CSRF token", type: :request do
  let(:admin) { create(:user, name: "Rohan", admin: true) }
  let(:employee) { create(:user, name: "Meera") }

  # Sign in BEFORE arming forgery protection: the dummy app's test session
  # endpoint is an ordinary POST and would be rejected too.
  around do |example|
    sign_in admin
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  # The hidden token belonging to the form that posts to `action`.
  def token_for(action)
    form = Nokogiri::HTML(response.body).css("form").find { |f| f["action"] == action }
    expect(form).to be_present, "no form posting to #{action} on the page"
    form.at_css("input[name='authenticity_token']")&.[]("value")
  end

  def expect_decidable(show_path, decide_path, params = {})
    get show_path
    expect(response).to have_http_status(:ok)

    post decide_path, params: params.merge(authenticity_token: token_for(decide_path))
    expect(response).to have_http_status(:found)
  end

  describe "comp-off" do
    let!(:co_type) { create(:leave_type, :comp_off, code: "CO", name: "Comp off") }
    let(:request_row) { create(:comp_off_request, user: employee) }

    it "rejects with the token the reject form actually rendered" do
      expect_decidable("/hr/admin/comp_off_requests/#{request_row.id}",
                       "/hr/admin/comp_off_requests/#{request_row.id}/reject",
                       decision_note: "No proof of work that day")
      expect(request_row.reload).to be_rejected
    end

    it "approves with the token the approve form actually rendered" do
      expect_decidable("/hr/admin/comp_off_requests/#{request_row.id}",
                       "/hr/admin/comp_off_requests/#{request_row.id}/approve")
      expect(request_row.reload).to be_approved
    end
  end

  describe "leave" do
    let(:request_row) { create(:leave_request, user: employee) }

    it "rejects with the token the reject form actually rendered" do
      expect_decidable("/hr/admin/leave_requests/#{request_row.id}",
                       "/hr/admin/leave_requests/#{request_row.id}/reject",
                       decision_note: "Peak departure week")
      expect(request_row.reload).to be_rejected
    end
  end

  describe "regularization" do
    let(:request_row) { create(:regularization_request, user: employee) }

    it "rejects with the token the reject form actually rendered" do
      expect_decidable("/hr/admin/regularization_requests/#{request_row.id}",
                       "/hr/admin/regularization_requests/#{request_row.id}/reject",
                       decision_note: "Raise it with your manager first")
      expect(request_row.reload).to be_rejected
    end
  end

  # The structural guard: `formaction` retargets a form without re-minting its
  # token, so it can never be right on a POST form in this engine.
  it "has no view retargeting a form with formaction" do
    offenders = Dir[HrLite::Engine.root.join("app/views/**/*.erb")].select do |path|
      # ERB comments explaining WHY it is banned are not offenders.
      File.read(path).gsub(/<%#.*?%>/m, "").include?("formaction")
    end
    expect(offenders).to be_empty, "formaction breaks per-form CSRF tokens: #{offenders.join(', ')}"
  end
end
