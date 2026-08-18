module HrLite
  # Everything waiting on the signed-in person, in one place. Before this,
  # an approver had to visit four screens to find out whether anybody was
  # waiting on them, and nothing told them if a request had gone stale.
  #
  # Employee tier on purpose: holding an approval IS the authorisation. A
  # manager, a stand-in covering for one, and a director all reach the same
  # screen and each sees only their own rows.
  class ApprovalsController < ApplicationController
    def index
      @approvals = paginate(mine.includes(:step, :subject).order(:created_at))
      @delegations = ApprovalDelegation.live_on(Date.current)
                                       .where(from_user_id: hr_current_user.id)
                                       .includes(:to_user)
      @covering_for = ApprovalDelegation.live_on(Date.current)
                                        .where(to_user_id: hr_current_user.id)
                                        .includes(:from_user)
    end

    private

    # Rows addressed to this person, plus rows belonging to anybody who has
    # delegated to them while they are away.
    def mine
      standing_in_for = ApprovalDelegation.live_on(Date.current)
                                          .where(to_user_id: hr_current_user.id)
                                          .pluck(:from_user_id)
      Approval.pending.where(approver_id: [ hr_current_user.id, *standing_in_for ])
    end
  end
end
