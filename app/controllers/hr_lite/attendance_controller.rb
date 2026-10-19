module HrLite
  # Employee self-service punch surface. Always operates on hr_current_user —
  # there is no user param, so punching for someone else is structurally
  # impossible.
  class AttendanceController < ApplicationController
    def show
      @month = parse_month_param(params[:month])
      @record = AttendanceRecord.find_by(user_id: hr_current_user.id, date: Date.current)
      @day_status = DayStatus.new(user: hr_current_user, range: @month.beginning_of_month..@month.end_of_month)
      @counts = @day_status.counts
      @counts[:absent] -= 1 if @month.all_month.cover?(Date.current) && @day_status.for(Date.current).kind == :absent
      @pending_dates = RegularizationRequest.pending.where(user_id: hr_current_user.id, date: @month.all_month).pluck(:date).to_set
      # ?day= opens the day detail; garbage (parsed as today), other months and the future open nothing.
      day = parse_date_param(params[:day])
      @day = day if params[:day] == day.iso8601 && @month.all_month.cover?(day) && day <= Date.current
      @day_info = @day_status.for(@day) if @day
      @day_ticket = RegularizationRequest.where(user_id: hr_current_user.id, date: @day).recent_first.first if @day
    end

    def check_in
      punch(:check_in)
    end

    def check_out
      punch(:check_out)
    end

    # Saving locks the slot for the period; a locked one only HR changes.
    def slot
      raise ActiveRecord::RecordNotFound unless HrLite.config.attendance_slots

      period = params[:period].to_s
      to = AttendanceSlot.ends_on_for(period, Date.current)
      if AttendanceSlot.where(user_id: hr_current_user.id, locked: true).overlapping(Date.current, to).exists?
        return redirect_to attendance_path, alert: "Your slot is locked for that period. Ask HR to change it."
      end
      # Today's penalty was priced on the slot at check-in; picking one now would rewrite it.
      if AttendanceRecord.where(user_id: hr_current_user.id, date: Date.current).where.not(check_in_at: nil).exists?
        return redirect_to attendance_path, alert: "Pick your slot before checking in."
      end

      slot = AttendanceSlot.new(user_id: hr_current_user.id, set_by_id: hr_current_user.id, period: period,
                                start_minute: params[:start_minute].to_i, starts_on: Date.current, ends_on: to)
      if slot.save
        redirect_to attendance_path, notice: "Slot #{AttendanceSlot.label(slot.start_minute)} saved and locked until #{to.strftime('%d %b')}."
      else
        redirect_to attendance_path, alert: slot.errors.full_messages.to_sentence
      end
    end

    private

    def punch(kind)
      # The browser held the tap (location blocked or not found): log it, file nothing.
      if params[:held]
        geo = AttendancePuncher::GEO_STATUSES.include?(params[:geo_status]) ? params[:geo_status] : "unavailable"
        log_refused(kind, "Location not picked up on the phone (#{geo})")
        return head(:no_content)
      end

      field = params.fetch(:field, {}).permit(:mode, :purpose, :place).to_h
      result = AttendancePuncher.call(user: hr_current_user, kind: kind, field: field, travel: params[:place] == "travel",
                                      save_home: params[:save_home] == "1" || params[:place] == "home", **punch_params.to_h.symbolize_keys)
      if result.ok?
        time = Time.current.strftime("%H:%M")
        redirect_to attendance_path, notice: "#{kind == :check_in ? 'Checked in' : 'Checked out'} at #{time}."
      else
        log_refused(kind, result.error)
        flash[:punch_offer] = result.offer.to_s if result.offer
        redirect_to attendance_path, alert: result.error
      end
    end

    # The person's summary lists these per day, so HR can see why a day is Absent.
    def log_refused(kind, error)
      AuditLog.record!(action: "attendance.punch_refused", subject: hr_current_user, actor: hr_current_user,
                       changes: { "kind" => kind.to_s, "error" => error })
    end

    def punch_params
      params.permit(:lat, :lng, :accuracy_m, :geo_status)
    end
  end
end
