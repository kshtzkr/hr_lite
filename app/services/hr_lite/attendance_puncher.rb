module HrLite
  # The single write path for employee punches. Race-safe (DB unique index +
  # row lock + in-lock re-check). A punch outside every office radius is
  # recorded AND flagged; one without GPS is too, unless
  # config.require_punch_location refuses it.
  class AttendancePuncher
    # What the browser can legitimately report (geo_punch.js).
    GEO_STATUSES = %w[ok denied unavailable timeout insecure].freeze
    OFF_SITE_MESSAGE = "You are not within the office location. Please request Work From Home (WFH) approval from HR.".freeze
    HOME_OFF_SITE_MESSAGE = "You are outside your registered WFH location. Please select an approved location " \
                            "or switch to Travelling Mode if you are travelling.".freeze
    NO_HOME_MESSAGE = "You have WFH today but no approved WFH location. Register one under WFH locations and ask HR to approve it.".freeze
    FIELD_MODES = %w[travelling outside_meeting].freeze

    Result = Struct.new(:record, :error, keyword_init: true) do
      def ok? = error.nil?
    end

    # field: { mode:, purpose:, place: } — a field-staff check-in away from the office.
    def self.call(user:, kind:, lat: nil, lng: nil, accuracy_m: nil, geo_status: "ok", field: {})
      new(user, kind.to_sym, lat, lng, accuracy_m, geo_status.to_s, field.to_h.symbolize_keys).call
    end

    def initialize(user, kind, lat, lng, accuracy_m, geo_status, field = {})
      @user = user
      @field = field.transform_values { |v| v.to_s.strip.presence }.compact
      @kind = kind
      @lat = lat.presence
      @lng = lng.presence
      @accuracy_m = accuracy_m.presence
      # Client-supplied and rendered straight into the admin-facing flag note.
      # Anything outside the browser's real permission states is not evidence:
      # a blank one (JS never ran) produced "without GPS ()", and a crafted one
      # let an employee write reassuring text onto their own flag.
      @geo_status = GEO_STATUSES.include?(geo_status.to_s) ? geo_status.to_s : "unavailable"
    end

    def call
      if HrLite.config.require_punch_location && (@lat.nil? || @lng.nil?)
        return Result.new(error: "Location is required to punch. Turn on location and try again, " \
                                 "or raise a regularization ticket.")
      end

      if (error = geofence_error)
        return Result.new(error: error)
      end

      record = resolve_record
      return Result.new(error: "No open check-in to close.") if record.nil?

      record.with_lock do
        case @kind
        when :check_in
          return Result.new(record: record, error: already_in_message(record)) if record.check_in_at.present?

          stamp(record, :check_in)
          record.work_mode = @mode
          record.work_location_id = @location&.id
          record.wfh_request_id = @wfh&.id if @mode == "wfh"
        when :check_out
          return Result.new(record: record, error: "Check in first.") if record.check_in_at.blank?

          stamp(record, :check_out) # repeat check-out overwrites: last out wins
        else
          return Result.new(error: "Unknown punch #{@kind}.")
        end

        apply_geo_flags(record)
        record.save!
        apply_slot_rules(record) if @kind == :check_in && HrLite.config.attendance_slots
        track_work_mode(record) if HrLite.config.office_geofence
      end
      notify_if_flagged(record)
      Result.new(record: record)
    end

    private

    def resolve_record
      if @kind == :check_out
        today = AttendanceRecord.find_by(user_id: @user.id, date: Date.current)
        return today if today&.check_in_at.present?

        # Post-midnight close of yesterday's open punch (office night, IST).
        return AttendanceRecord.for_date(Date.current - 1)
                               .missing_checkout.find_by(user_id: @user.id)
      end

      AttendanceRecord.find_or_create_by!(user_id: @user.id, date: Date.current)
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    # config.office_geofence decides where a check-in may come from, and so
    # the day's work_mode: inside an office radius is office (even on a WFH
    # day); a field-staff check-in that says where and why is travelling or
    # outside_meeting; approved WFH (dated or permanent) must be within the
    # active approved home location's fence. Anything else is refused.
    def geofence_error
      return unless @kind == :check_in && HrLite.config.office_geofence && OfficeLocation.active.exists?
      return location_error unless @lat && @lng
      if in_office?
        @mode = "office"
        return
      end

      profile = EmployeeProfile.find_by(user_id: @user.id)
      if profile&.field_staff && FIELD_MODES.include?(@field[:mode])
        return "Say why and where you are checking in from the field." unless @field[:purpose] && @field[:place]

        @mode = @field[:mode]
        return
      end

      @wfh = WfhRequest.approved_for(@user.id, Date.current)
      return OFF_SITE_MESSAGE unless @wfh || profile&.permanent_wfh

      @location = WorkLocation.active_for(@user.id)
      return NO_HOME_MESSAGE unless @location
      return HOME_OFF_SITE_MESSAGE unless precise_within?(WorkLocation::FENCE_M) && @location.covers?(@lat, @lng)

      @mode = "wfh"
      nil
    end

    # Check-in opens the day's system-set mode; check-out ends everything and
    # opens Offline. The timeline keeps every earlier row.
    def track_work_mode(record)
      if @kind == :check_in
        WorkModeEvent.start!(user_id: @user.id, mode: record.work_mode || "office", source: "system",
                             attendance_record: record, wfh_request_id: record.wfh_request_id,
                             work_location_id: record.work_location_id, title: @field[:purpose], destination: @field[:place])
      else
        WorkModeEvent.close_all!(@user.id, "checked_out")
        WorkModeEvent.start!(user_id: @user.id, mode: "offline", source: "system", attendance_record: record)
      end
    end

    def location_error
      "We could not read your location (#{@geo_status}). Turn location on and try again, " \
        "or request Work From Home (WFH) approval from HR."
    end

    def precise_within?(metres) = @accuracy_m.to_f.positive? && @accuracy_m.to_f <= metres

    def in_office?
      OfficeLocation.active.any? do |office|
        precise_within?(office.radius_m) && Geo.distance_m(office.lat, office.lng, @lat.to_f, @lng.to_f) <= office.radius_m
      end
    end

    def stamp(record, side)
      record.public_send("#{side}_at=", Time.current)
      record.public_send("#{side}_lat=", @lat)
      record.public_send("#{side}_lng=", @lng)
      record.public_send("#{side}_accuracy_m=", @accuracy_m)
    end

    def already_in_message(record)
      "Already checked in at #{record.check_in_at.in_time_zone(HrLite.config.time_zone).strftime('%H:%M')}."
    end

    # Late ladder against slot + buffer; after 11:00 also +1h on the next two
    # working days; after 11:30 the day is a half day. The buffer shifts all three.
    def apply_slot_rules(record)
      local = record.check_in_at.in_time_zone(HrLite.config.time_zone)
      arrived = local.hour * 60 + local.min - EmployeeProfile.where(user_id: @user.id).pick(:buffer_minutes).to_i
      late = AttendanceSlot.penalty_minutes(arrived - AttendanceSlot.start_minute_for(@user.id, record.date))
      penalize(record, record.date, late, "late") if late.positive?
      return if arrived <= AttendanceSlot::CARRY_AFTER_MINUTE

      AttendancePenalty.next_working_days(record.date, 2).each { |day| penalize(record, day, 60, "late_carry") }
      return if arrived <= AttendanceSlot::HALF_DAY_AFTER_MINUTE

      record.update!(status: "half_day", regularization_note: AttendanceRecord::LATE_HALF_DAY_NOTE)
    end

    def penalize(record, date, minutes, reason)
      AttendancePenalty.create!(user_id: @user.id, date: date, minutes: minutes, reason: reason, attendance_record: record)
    end

    def apply_geo_flags(record)
      label = @kind == :check_in ? "Check-in" : "Check-out"

      if @lat.nil? || @lng.nil?
        reason = @geo_status == "ok" ? "unavailable" : @geo_status
        record.add_flag!("#{label} without GPS (#{reason})")
      elsif record.work_mode && record.work_mode != "office"
        nil # WFH or field work: off-site is the point
      elsif OfficeLocation.active.exists? && !OfficeLocation.covering?(@lat, @lng)
        office = OfficeLocation.nearest(@lat, @lng)
        distance_km = (Geo.distance_m(office.lat, office.lng, @lat, @lng) / 1000.0).round(1)
        accuracy = @accuracy_m ? " (±#{@accuracy_m} m)" : ""
        record.add_flag!("#{label} #{distance_km} km from #{office.name}#{accuracy}")
      end
    end

    def notify_if_flagged(record)
      return unless record.saved_changes.key?("flag_note") && record.flagged?

      Notifications.publish(
        "attendance.flagged",
        title: "Flagged punch — #{HrLite.display_name(@user)}",
        body: record.flag_note,
        path: "/admin/attendances?date=#{record.date}",
        bell_to: HrLite.admin_users
      )
    end
  end
end
