module HrLite
  # Opts a model into the routed, multi-step approval flow — WITHOUT taking
  # over what its decisions mean.
  #
  # The model keeps its own `approve!` / `reject!`: those are the domain
  # actions, and for leave one of them credits a balance inside a row lock.
  # This concern only asks "is it this person's turn, and does their answer
  # settle it?" and hands back an outcome for the model to act on.
  #
  # A subject type with no active flow behaves exactly as it did before —
  # single decision, whoever holds the permission. That is what lets the four
  # existing modules migrate one at a time instead of all at once.
  module Approvable
    extend ActiveSupport::Concern

    included do
      has_many :approvals, as: :subject, class_name: "HrLite::Approval", dependent: :destroy
      after_create_commit :open_approval_route
    end

    def approval_route = @approval_route ||= ApprovalRoute.new(self)

    def routed_for_approval? = approval_route.routed?

    # The rows still waiting, newest rung first — what the show screen lists.
    def pending_approvals = approvals.pending.order(:position)

    def approval_for(user)
      return nil if user.nil?

      pending_approvals.detect { |approval| approval.answerable_by?(user) }
    end

    # Whether this person is the one being waited on. Unrouted subjects fall
    # back to the permission check the module already used.
    def awaiting?(user) = approval_for(user).present?

    # The whole story, for the approval screen: who decided what, in order,
    # including the rungs that were skipped and why.
    def approval_history = approvals.order(:position, :id)

    private

    def open_approval_route
      approval_route.open! if approval_route.routed?
    end
  end
end
