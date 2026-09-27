module HrLite
  module Admin
    # Write a policy or an announcement and send it to everyone. A policy asks
    # to be acknowledged; an announcement does not. Same title again = the
    # next version.
    class PoliciesController < ApplicationController
      before_action { hr_require_permission!("policy.manage", scope: :all) }

      def index
        @policies = Policy.newest_first
      end

      def new
        @policy = Policy.new(effective_from: Date.current, acknowledgement_required: true)
      end

      def create
        @policy = Policy.new(params.require(:policy).permit(:title, :body, :effective_from, :acknowledgement_required)
                                   .merge(published: true))
        @policy.version = (Policy.where(title: @policy.title).maximum(:version) || 0) + 1
        if @policy.save
          redirect_to admin_policies_path, notice: "Published — everyone has been told."
        else
          render :new, status: :unprocessable_entity
        end
      end
    end
  end
end
