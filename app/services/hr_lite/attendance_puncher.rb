module HrLite
  # The single write path for employee punches. Race-safe (DB unique index +
  # row lock + in-lock re-check), never blocked by geolocation: a punch
  # without GPS or outside every office radius is recorded AND flagged —
  # denying GPS must not stop anyone from working.
  class AttendancePuncher
    Result = Struct.new(:record, :error, keyword_init: true) do
      def ok? = error.nil?
    end

    def self.call(user:, kind:, lat: nil, lng: nil, accuracy_m: nil, geo_status: "ok")
      new(user, kind.to_sym, lat, lng, accuracy_m, geo_status.to_s).call
    end

    def initialize(user, kind, lat, lng, accuracy_m, geo_status)
      @user = user
      @kind = kind
      @lat = lat.presence
      @lng = lng.presence
      @accuracy_m = accuracy_m.presence
      @geo_status = geo_status
    end

    def call
      record = resolve_record
      return Result.new(error: "No open check-in to close.") if record.nil?

      record.with_lock do
        case @kind
        when :check_in
          return Result.new(record: record, error: already_in_message(record)) if record.check_in_at.present?

          stamp(record, :check_in)
        when :check_out
          return Result.new(record: record, error: "Check in first.") if record.check_in_at.blank?

          stamp(record, :check_out) # repeat check-out overwrites: last out wins
        else
          return Result.new(error: "Unknown punch #{@kind}.")
        end

        apply_geo_flags(record)
        record.save!
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

    def stamp(record, side)
      record.public_send("#{side}_at=", Time.current)
      record.public_send("#{side}_lat=", @lat)
      record.public_send("#{side}_lng=", @lng)
      record.public_send("#{side}_accuracy_m=", @accuracy_m)
    end

    def already_in_message(record)
      "Already checked in at #{record.check_in_at.in_time_zone(HrLite.config.time_zone).strftime('%H:%M')}."
    end

    def apply_geo_flags(record)
      label = @kind == :check_in ? "Check-in" : "Check-out"

      if @lat.nil? || @lng.nil?
        reason = @geo_status == "ok" ? "unavailable" : @geo_status
        record.add_flag!("#{label} without GPS (#{reason})")
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
