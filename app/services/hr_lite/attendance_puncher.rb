module HrLite
  # The single write path for employee punches. Race-safe (DB unique index +
  # row lock + in-lock re-check). A punch outside every office radius is
  # recorded AND flagged; one without GPS is too, unless
  # config.require_punch_location refuses it.
  class AttendancePuncher
    # What the browser can legitimately report (geo_punch.js).
    GEO_STATUSES = %w[ok denied unavailable timeout insecure].freeze
    OFF_SITE_MESSAGE = "You are not within the office location. Please request Work From Home (WFH) approval from HR.".freeze
    HOME_ASK_MESSAGE = "You are not at any of your home locations. Is this your home location? " \
                       "Answer on the card below and check in again.".freeze
    HOME_CAP_MESSAGE = "You already have #{WorkLocation::MAX_LIVE} home locations. Ask HR to change one, or choose Travelling.".freeze
    HOME_FIX_MESSAGE = "Your location is not precise enough to save as home (#{WorkLocation::MAX_ACCURACY_M} m or better). " \
                       "Step outside or wait for GPS and try again.".freeze
    TRAVEL_OUT_MESSAGE = "You checked in at home and are away from your home locations now. Choose Travelling to check out here.".freeze
    FIELD_MODES = %w[travelling outside_meeting].freeze

    # offer: :home or :travel — the choice the punch card should put in front of the person.
    Result = Struct.new(:record, :error, :offer, keyword_init: true) do
      def ok? = error.nil?
    end

    # field: { mode:, purpose:, place: } — a field-staff check-in away from the office.
    # travel: a WFH punch away from every home; save_home: keep this spot as a home.
    def self.call(user:, kind:, lat: nil, lng: nil, accuracy_m: nil, geo_status: "ok", field: {}, travel: false, save_home: false)
      new(user, kind.to_sym, lat, lng, accuracy_m, geo_status.to_s, field.to_h.symbolize_keys, travel:, save_home:).call
    end

    def initialize(user, kind, lat, lng, accuracy_m, geo_status, field = {}, travel: false, save_home: false)
      @user = user
      @travel = travel
      @save_home = save_home
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
        return Result.new(error: error, offer: @offer)
      end

      record = resolve_record
      return Result.new(error: "No open check-in to close.") if record.nil?
      if @kind == :check_out && (error = check_out_place_error(record))
        return Result.new(error: error, offer: @offer)
      end

      record.with_lock do
        case @kind
        when :check_in
          if (reopen = record.check_out_at.present?)
            # Checking in again reopens the day: the first check-in stands, the
            # gap stays Offline on the work-mode timeline.
            unless record.recheck_in_open?
              s = Setting.instance
              return Result.new(record: record, error: "Check in again is open once a day, #{s.recheck_in_from}–#{s.recheck_in_until}.")
            end

            record.assign_attributes(check_out_at: nil, check_out_lat: nil, check_out_lng: nil, check_out_accuracy_m: nil,
                                     check_out_place: nil, check_out_home_m: nil, check_out_work_location_id: nil, rechecked_in_at: Time.current)
          else
            return Result.new(record: record, error: already_in_message(record)) if record.check_in_at.present?

            stamp(record, :check_in)
            record.work_mode = @mode
            record.work_location_id = @location&.id
            record.wfh_request_id = @wfh&.id if @mode == "wfh"
            record.add_flag!("WFH request pending HR approval: #{@wfh.reason}") if @wfh&.pending?
          end
        when :check_out
          return Result.new(record: record, error: "Check in first.") if record.check_in_at.blank?

          stamp(record, :check_out) # repeat check-out overwrites: last out wins
          record.check_out_work_location_id = @location&.id
        else
          return Result.new(error: "Unknown punch #{@kind}.")
        end

        apply_geo_flags(record)
        record.save!
        apply_slot_rules(record) if @kind == :check_in && !reopen && HrLite.config.attendance_slots
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
    # fence of any of their approved homes (the nearest one is picked), or
    # saved as a new home on the spot, or Travelling. Anything else is refused.
    def geofence_error
      return unless @kind == :check_in && HrLite.config.office_geofence && OfficeLocation.active.exists?
      return location_error unless @lat && @lng
      if in_office?
        @mode, @place = "office", "office"
        return
      end

      profile = EmployeeProfile.find_by(user_id: @user.id)
      if profile&.field_staff && FIELD_MODES.include?(@field[:mode])
        return "Say why and where you are checking in from the field." unless @field[:purpose] && @field[:place]

        @mode, @place = @field[:mode], "travel"
        return
      end

      # A request HR has not decided yet still lets the person work; the day is flagged for HR.
      @wfh = WfhRequest.approved_for(@user.id, Date.current) || WfhRequest.pending_for(@user.id, Date.current)
      return OFF_SITE_MESSAGE unless @wfh || profile&.permanent_wfh

      @mode, @place = "wfh", "home"
      return if (@location = covering_home)
      return save_home if @save_home

      @offer = :home
      return HOME_ASK_MESSAGE unless @travel

      @mode, @place = "travelling", "travel"
      nil
    end

    # A day begun at home or travelling ends at a home, in the office, or
    # travelling; leaving home for elsewhere has to be said out loud.
    def check_out_place_error(record)
      return unless %w[home travel].include?(record.check_in_place) && @lat && @lng

      if in_office? then @place = "office"
      elsif (@location = covering_home) then @place = "home"
      elsif @travel || record.check_in_place == "travel" then @place = "travel"
      else
        @offer = :travel
        return TRAVEL_OUT_MESSAGE
      end
      nil
    end

    def homes = @homes ||= WorkLocation.approved.where(user_id: @user.id).to_a

    # The nearest approved home whose fence this fix is inside; it becomes the active one.
    def covering_home
      return unless precise_within?(WorkLocation::FENCE_M)

      home = homes.select { |h| h.covers?(@lat, @lng) }.min_by { |h| Geo.distance_m(h.lat, h.lng, @lat.to_f, @lng.to_f) }
      home&.make_active! unless home&.active
      home
    end

    # "Is this your home?" — yes. Saved approved and active at once while
    # the person has fewer than MAX_LIVE homes; HR sees it in the audit log.
    def save_home
      return HOME_FIX_MESSAGE unless precise_within?(WorkLocation::MAX_ACCURACY_M)

      count = WorkLocation.live.where(user_id: @user.id).count
      return HOME_CAP_MESSAGE if count >= WorkLocation::MAX_LIVE

      @location = WorkLocation.create!(user_id: @user.id, name: "Home #{count + 1}", lat: @lat, lng: @lng,
                                       accuracy_m: @accuracy_m, status: "approved", decided_at: Time.current)
      @location.make_active!
      @homes = nil
      AuditLog.record!(action: "work_location.self_saved", subject: @location, actor: @user, changes: { "name" => @location.name })
      nil
    end

    # Metres to the nearest approved home; nil without a fix or a home.
    def home_m
      return unless @lat && @lng

      homes.map { |h| Geo.distance_m(h.lat, h.lng, @lat.to_f, @lng.to_f) }.min&.round
    end

    # Check-in opens the day's system-set mode; check-out ends everything and
    # opens Offline. The timeline keeps every earlier row.
    def track_work_mode(record)
      if @kind == :check_in
        WorkModeEvent.start!(user_id: @user.id, mode: @mode || record.work_mode || "office", source: "system",
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
      record.public_send("#{side}_place=", @place || ("office" if @lat && @lng && in_office?))
      record.public_send("#{side}_home_m=", home_m)
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

      AttendancePenalty.next_working_days(record.user_id, record.date, 2).each { |day| penalize(record, day, 60, "late_carry") }
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
