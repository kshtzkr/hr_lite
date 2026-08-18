module HrLite
  module Admin
    class LeaveRequestsController < BaseController
      def index
        scope = LeaveRequest.includes(:leave_type, :user).recent_first
        @status = params[:status].presence_in(LeaveRequest::STATUSES) || "pending"
        # A manager's queue is their own reports. HR's is everybody's. Scoping
        # the LIST as well as the decision matters: an index that shows a row
        # the member action then refuses is a worse screen than one that never
        # showed it.
        @requests = paginate(hr_scope(scope.where(status: @status), "leave.view"))
      end

      def show
        @request = decidable.includes(:leave_type).find(params[:id])
        @balance = @request.balance
      end

      def approve
        request = find_decidable
        if request.approve!(actor: hr_current_user, note: params[:decision_note].presence)
          redirect_to admin_leave_requests_path, notice: "Leave approved."
        else
          redirect_to admin_leave_request_path(request),
                      alert: "Cannot approve — balance no longer covers this request."
        end
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_leave_request_path(request), alert: "Only pending requests can be decided."
      end

      # LeaveRequest#cancellable_by? has always allowed an admin to call off
      # approved future leave, but no route reached it — the only cancel action
      # was the employee's own, scoped to their own rows. A trip called off
      # while the person was unreachable, or after they were offboarded, could
      # not be released at all, and the quota stayed spent.
      def cancel
        request = find_decidable
        if request.cancellable_by?(hr_current_user)
          request.cancel!(actor: hr_current_user)
          redirect_to admin_leave_requests_path, notice: "Leave cancelled — the balance is released."
        else
          redirect_to admin_leave_request_path(request),
                      alert: "Only pending leave, or approved leave that has not started, can be cancelled."
        end
      end

      def reject
        request = find_decidable
        note = params[:decision_note].to_s.strip
        if note.blank?
          return redirect_to admin_leave_request_path(request), alert: "A note is required to reject."
        end

        request.reject!(actor: hr_current_user, note: note)
        redirect_to admin_leave_requests_path, notice: "Leave rejected."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_leave_request_path(request), alert: "Only pending requests can be decided."
      end

      private

      # Requests this person may actually decide. A manager reaching for
      # somebody else's report gets a 404 through the scoped relation rather
      # than a 403 — the same shape every employee-tier screen already uses,
      # and it does not confirm that the other person exists.
      def decidable
        hr_scope(LeaveRequest.all, "leave.approve")
      end

      def find_decidable = decidable.find(params[:id])
    end
  end
end
