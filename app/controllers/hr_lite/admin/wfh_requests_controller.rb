module HrLite
  module Admin
    # WFH board (counts, who is home on a date, every schedule) and the
    # decision screen. Viewing is attendance.view, deciding and changing attendance.manage.
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

        load_home(visible)

        scoped = @status ? range.where(status: @status) : range
        @requests = paginate(scoped.includes(:user).order(:user_id, :start_date, :id))
      end

      # HR gives WFH outright, approved on creation, up to 60 days.
      def create
        employee = HrLite.user_klass.find(params[:user_id])
        hr_require_reach!("attendance.manage", employee)
        raise ActiveRecord::RecordNotFound if employee.id == hr_current_user.id

        request = WfhRequest.grant!(user_id: employee.id, by: hr_current_user, start_date: params[:start_date],
                                    end_date: params[:end_date], reason: params[:reason].to_s.strip)
        redirect_to admin_wfh_requests_path, notice: "WFH given to #{hr_display_name(employee)} for #{request.dates_label}."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_wfh_requests_path, alert: "Could not give WFH: #{e.record.errors.full_messages.to_sentence}"
      end

      def show
        @request = hr_scope(WfhRequest.all, "attendance.view").find(params[:id])
        @decidable = decidable.exists?(@request.id)
      end

      def approve
        request = decidable.find(params[:id])
        request.approve!(actor: hr_current_user, note: params[:decision_note].to_s.strip.presence)
        redirect_to admin_wfh_requests_path, notice: "WFH approved for #{hr_display_name(request.user)}."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_wfh_request_path(request), alert: reason_for(e, "Only pending requests can be decided.")
      end

      def reject
        request = decidable.find(params[:id])
        note = params[:decision_note].to_s.strip
        return redirect_to admin_wfh_request_path(request), alert: "A remark is required to reject." if note.blank?

        request.reject!(actor: hr_current_user, note: note)
        redirect_to admin_wfh_requests_path, notice: "WFH rejected."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_wfh_request_path(request), alert: reason_for(e, "Only pending requests can be decided.")
      end

      # HR changes an approved or rejected request: dates (past allowed) and/or decision, with a reason.
      def update
        request = decidable.where(status: %w[approved rejected]).find(params[:id])
        note = params[:decision_note].to_s.strip
        return redirect_to admin_wfh_request_path(request), alert: "A reason is required to change WFH." if note.blank?

        request.change!(actor: hr_current_user, start_date: params[:start_date], end_date: params[:end_date],
                        status: params[:status].presence_in(%w[approved rejected]) || request.status, note: note)
        redirect_to admin_wfh_request_path(request), notice: "WFH changed for #{hr_display_name(request.user)}."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_wfh_request_path(request), alert: "Could not change WFH: #{e.record.errors.full_messages.to_sentence}"
      end

      private

      # Nobody decides their own request; out-of-scope ids are a 404.
      def decidable = hr_scope(WfhRequest.all, "attendance.manage").where.not(user_id: hr_current_user.id)

      HomeRow = Struct.new(:user, :label, :request)

      # Everyone home on @on: an approved request, else permanent WFH. One row a person.
      def load_home(visible)
        rows = visible.approved.overlapping(@on, @on).includes(:user).order(:user_id)
                      .map { |r| HomeRow.new(r.user, r.dates_label, r) }.uniq { |row| row.user.id }
        permanent = hr_scope(EmployeeProfile.where(permanent_wfh: true), "attendance.view")
        permanent = permanent.where(user_id: filtered_user_ids) if filtered_user_ids
        ids = permanent.pluck(:user_id) - rows.map { |row| row.user.id }
        rows += HrLite.user_klass.where(id: ids).map { |u| HomeRow.new(u, "Permanent WFH", nil) }
        @records = AttendanceRecord.where(date: @on, user_id: rows.map { |row| row.user.id }).where.not(check_in_at: nil).index_by(&:user_id)
        @home_count = rows.size
        @home = @attendance ? rows.select { |row| @records.key?(row.user.id) == (@attendance == "checked_in") } : rows
        @grantable = HrLite.employees.select { |u| u.id != hr_current_user.id && hr_reaches?("attendance.manage", u) }
      end

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
