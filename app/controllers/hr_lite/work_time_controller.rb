module HrLite
  # "My work time": the signed-in person's own analytics. There is no user
  # param — nobody can read someone else's here.
  class WorkTimeController < ApplicationController
    before_action { raise ActiveRecord::RecordNotFound unless HrLite.config.office_geofence }

    def show
      @period, @period_error = WorkModeDurations::Period.from_params(params, Date.current)
      @result = WorkModeDurations.call([ hr_current_user.id ], @period)
      @records = AttendanceRecord.where(user_id: hr_current_user.id, date: @period.from..@period.to)
                                 .where.not(check_in_at: nil).order(:date).limit(400)
    end
  end
end
