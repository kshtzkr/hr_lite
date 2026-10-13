module HrLite
  # The everyone-visible team board: who's in, who's out, who's on leave,
  # hours worked — for any date. Transparency by design; shows punch times
  # and leave types only, never reasons or personal data.
  class TeamController < ApplicationController
    def show
      @date = parse_date_param(params[:date])
      @board = TeamDay.new(date: @date)
      return unless HrLite.config.office_geofence && @date == Date.current

      # Live work modes: labels only (Office / Home / …), never where home is.
      @statuses = WorkStatus.for_users(@board.rows.map { |r| r.user.id })
      @departments = @board.rows.filter_map { |r| r.profile&.department.presence }.uniq.sort
      @mode = params[:mode].presence_in(WorkModeEvent::MODES.keys + WorkStatus::DERIVED.keys)
      @availability = params[:availability].presence_in(%w[available unavailable])
      @rows = @board.rows.select do |r|
        st = @statuses[r.user.id]
        (params[:department].blank? || r.profile&.department == params[:department]) &&
          (@mode.nil? || [ st.primary.mode, st.overlay&.mode ].include?(@mode)) &&
          (@availability.nil? || st.available? == (@availability == "available"))
      end
    end
  end
end
