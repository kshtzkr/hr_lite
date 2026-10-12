module HrLite
  module Admin
    # WFH board (counts, who is home on a date, every schedule) and the
    # decision screen. Viewing is attendance.view, deciding attendance.manage.
    class WfhRequestsController < BaseController
      def index
        @from = params[:from].present? ? parse_date_param(params[:from]) : Date.current
        @to = [ params[:to].present? ? parse_date_param(params[:to]) : @from + WfhRequest::MAX_DAYS_AHEAD, @from ].max
        @on = params[:on].present? ? parse_date_param(params[:on]) : Date.current
        @status = params[:status].presence_in(WfhRequest::STATUSES)
        @attendance = params[:attendance].presence_in(%w[checked_in not_checked_in])
        @departments = EmployeeProfile.where.not(department: [ nil, "" ]).distinct.order(:department).pluck(:department)

        visible = hr_scope(WfhRequest.all, "attendance.view")
        visible = visible.where(user_id: filtered_user_ids) if filtered_user_ids
        range = visible.overlapping(@from, @to)
        @kpis = {
          requested: range.distinct.count(:user_id),
          approved: range.approved.distinct.count(:user_id),
          pending: range.pending.count,
          rejected: range.where(status: "rejected").count
        }

        # One approved request per person per date (no overlaps), uniq anyway.
        @home = visible.approved.overlapping(@on, @on).includes(:user).order(:user_id).to_a.uniq(&:user_id)
        @punched = AttendanceRecord.where(date: @on, user_id: @home.map(&:user_id)).where.not(check_in_at: nil).pluck(:user_id).to_set
        @home_count = @home.size
        @home = @home.select { |r| @punched.include?(r.user_id) == (@attendance == "checked_in") } if @attendance

        scoped = @status ? range.where(status: @status) : range
        @requests = paginate(scoped.includes(:user).order(:user_id, :start_date, :id))
      end

      def show
        @request = hr_scope(WfhRequest.all, "attendance.view").find(params[:id])
        @decidable = decidable.exists?(@request.id)
      end

      def approve
        request = decidable.find(params[:id])
        request.approve!(actor: hr_current_user, note: params[:decision_note].to_s.strip.presence)
        redirect_to admin_wfh_requests_path, notice: "WFH approved for #{hr_display_name(request.user)}."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_wfh_request_path(request), alert: "Only pending requests can be decided."
      end

      def reject
        request = decidable.find(params[:id])
        note = params[:decision_note].to_s.strip
        return redirect_to admin_wfh_request_path(request), alert: "A remark is required to reject." if note.blank?

        request.reject!(actor: hr_current_user, note: note)
        redirect_to admin_wfh_requests_path, notice: "WFH rejected."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_wfh_request_path(request), alert: "Only pending requests can be decided."
      end

      private

      # Nobody decides their own request; out-of-scope ids are a 404.
      def decidable = hr_scope(WfhRequest.all, "attendance.manage").where.not(user_id: hr_current_user.id)

      def filtered_user_ids
        return @filtered_user_ids if defined?(@filtered_user_ids)

        ids = nil
        if (q = params[:q].to_s.strip.downcase).present?
          ids = HrLite.employees.select { |u| HrLite.display_name(u).to_s.downcase.include?(q) }.map(&:id)
        end
        if (dept = params[:department].presence)
          in_dept = EmployeeProfile.where(department: dept).pluck(:user_id)
          ids = ids ? ids & in_dept : in_dept
        end
        @filtered_user_ids = ids
      end
    end
  end
end
