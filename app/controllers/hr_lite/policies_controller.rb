module HrLite
  # What people are held to, and the button that says they have read it.
  class PoliciesController < ApplicationController
    before_action :require_reading!

    def index
      @policies = Policy.current.sort_by(&:title)
      @acknowledged = PolicyAcknowledgement.where(user_id: hr_current_user.id)
                                           .pluck(:policy_id).to_set
    end

    def show
      @policy = Policy.published.find(params[:id])
    end

    def acknowledge
      policy = Policy.published.find(params[:id])
      policy.acknowledge!(hr_current_user)
      redirect_to policies_path, notice: "Thank you — recorded against #{policy.title} v#{policy.version}."
    end

    private

    def require_reading! = hr_require_permission!("policy.view", scope: :all)
  end
end
