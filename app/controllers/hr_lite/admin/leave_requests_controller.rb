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

      # HR records leave somebody forgot to apply for. Approved on save, by the
      # person recording it; days beyond the balance become loss of pay.
      def new
        @request = LeaveRequest.new(start_date: Date.current, end_date: Date.current)
        @people = recordable
      end

      def create
        profile = recordable.find_by(employee_code: params[:employee_code].to_s.strip)
        @request = LeaveRequest.new(params.require(:leave_request).permit(:leave_type_id, :start_date, :end_date, :half_day, :half_day_part, :reason)
                                          .merge(user_id: profile&.user_id, created_by_id: hr_current_user.id))
        recorded = profile && LeaveRequest.transaction do
          (@request.save && @request.approve!(actor: hr_current_user, note: "Recorded by HR")) || raise(ActiveRecord::Rollback)
        end
        return redirect_to(admin_leave_request_path(@request), notice: "Leave recorded and approved.") if recorded

        @request.errors.add(:base, profile ? "Not enough comp-off credit" : "Pick an employee from the list") if @request.errors.empty?
        @people = recordable
        render :new, status: :unprocessable_entity
      end

      # Leave HR recorded is fixed in place, any time, with a reason.
      def edit
        @request = find_recorded
      end

      def update
        @request = find_recorded
        reason = params[:correction_reason].to_s.strip
        @request.errors.add(:base, "A reason is required to fix this leave") if reason.blank?
        attrs = params.require(:leave_request).permit(:leave_type_id, :start_date, :end_date, :half_day_part)
        if reason.present? && @request.correct!(actor: hr_current_user, attrs: attrs, reason: reason)
          return redirect_to(admin_leave_request_path(@request), notice: "Leave fixed.")
        end

        render :edit, status: :unprocessable_entity
      end

      def approve
        request = find_decidable
        if request.approve!(actor: hr_current_user, note: params[:decision_note].presence)
          redirect_to admin_leave_requests_path, notice: "Leave approved."
        else
          redirect_to admin_leave_request_path(request),
                      alert: "Cannot approve — comp-off credit no longer covers this request."
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
        note = params[:decision_note].to_s.strip
        if !request.cancellable_by?(hr_current_user)
          redirect_to admin_leave_request_path(request), alert: "This leave can no longer be cancelled."
        elsif note.blank?
          redirect_to admin_leave_request_path(request), alert: "A reason is required to cancel."
        else
          request.cancel!(actor: hr_current_user, note: note)
          redirect_to admin_leave_requests_path, notice: "Leave cancelled — the balance is released."
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
      # Nobody decides their own request: team scope includes the approver.
      def decidable
        hr_scope(LeaveRequest.all, "leave.approve").where.not(user_id: hr_current_user.id)
      end

      def find_decidable = decidable.find(params[:id])

      def find_recorded = decidable.approved.where.not(created_by_id: nil).where("created_by_id <> user_id").find(params[:id])

      def recordable = hr_scope(EmployeeProfile.includes(:user), "leave.approve").where.not(user_id: hr_current_user.id)
    end
  end
end
