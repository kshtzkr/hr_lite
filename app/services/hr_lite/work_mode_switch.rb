module HrLite
  # The one write path for a chosen work mode (employee or HR). A mode is a
  # status: it never changes where the day's attendance was authorised, and
  # nothing here touches the attendance record.
  class WorkModeSwitch
    SELECTABLE = %w[office wfh travelling outside_meeting meeting lunch short_break busy out_of_office].freeze
    OUT_OF_OFFICE_REASONS = { "personal" => "Personal errand", "medical" => "Medical", "family" => "Family",
                              "official" => "Official work", "other" => "Other" }.freeze

    Result = Struct.new(:event, :error) do
      def ok? = error.nil?
    end

    def self.call(...) = new(...).call

    CLEAR_AFTER = { "30" => 30.minutes, "60" => 1.hour, "240" => 4.hours, "today" => :today, "never" => nil }.freeze

    # A person's own status, Slack-style: works with or without a check-in
    # and clears itself on the chosen timer.
    def self.set_status(user:, text:, emoji:, clear_after:)
      now = Time.current
      span = CLEAR_AFTER.fetch(clear_after.to_s, :today)
      ends_at = span == :today ? now.in_time_zone(HrLite.config.time_zone).end_of_day : (span && now + span)
      event = WorkModeEvent.start!(user_id: user.id, mode: "custom", source: "employee", actor: user, at: now,
                                   title: text.to_s.strip.truncate(100).presence, emoji: emoji.to_s.strip.presence, ends_at: ends_at)
      WorkModeExpireJob.set(wait_until: ends_at).perform_later(event.id) if ends_at
      Result.new(event, nil)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(nil, e.record.errors.full_messages.to_sentence)
    end

    # params: title, client, destination, reason, minutes, until ("HH:MM" today)
    def initialize(user:, mode:, source:, actor:, params: {})
      @user = user
      @mode = mode.to_s
      @source = source
      @actor = actor
      @p = params.to_h.symbolize_keys.transform_values { |v| v.to_s.strip.presence }.compact
      @now = Time.current
    end

    def call
      return fail!("Pick a work mode.") unless SELECTABLE.include?(@mode)
      return fail!("A reason is required for an HR change.") if @source == "hr" && @p[:reason].blank?

      status = WorkStatus.for(@user.id, at: @now)
      return fail!("#{status.primary.label} today — work modes are off. Use the leave screen to change it.") if %w[holiday on_leave sick_leave].include?(status.primary.mode)
      return fail!("Check in first; your mode starts with your check-in.") unless checked_in?

      attrs = send("#{@mode}_attrs")
      return fail!(attrs) if attrs.is_a?(String)

      event = WorkModeEvent.start!(user_id: @user.id, mode: @mode, source: @source, actor: @actor, at: @now,
                                   attendance_record: @record, **attrs)
      WorkModeExpireJob.set(wait_until: event.ends_at).perform_later(event.id) if event.ends_at
      Result.new(event, nil)
    rescue ActiveRecord::RecordInvalid => e
      fail!(e.record.errors.full_messages.to_sentence)
    end

    private

    def fail!(message) = Result.new(nil, message)

    def checked_in?
      @record = AttendanceRecord.find_by(user_id: @user.id, date: @now.in_time_zone(HrLite.config.time_zone).to_date)
      @record&.check_in_at.present? && @record.check_out_at.nil?
    end

    def base = { reason: @p[:reason] }

    def office_attrs = base

    def wfh_attrs
      approved = WfhRequest.approved_for(@user.id, @record.date) ||
                 EmployeeProfile.where(user_id: @user.id).pick(:permanent_wfh)
      return "WFH needs an approved WFH request for today." unless approved

      base.merge(work_location_id: WorkLocation.active_for(@user.id)&.id)
    end

    def travelling_attrs
      return "Say where you are going and why." unless @p[:destination] && @p[:title]

      with_lead(base.merge(destination: @p[:destination], title: @p[:title], client: @p[:client])) { |a| timed(a, required: false) }
    end

    def outside_meeting_attrs
      return "Say who you are meeting and why." unless (@p[:client] || @p[:crm_ref]) && @p[:title]

      with_lead(base.merge(client: @p[:client], title: @p[:title], destination: @p[:destination])) { |a| timed(a, required: false) }
    end

    def meeting_attrs
      return "Give the meeting a title." unless @p[:title]

      with_lead(base.merge(title: @p[:title], client: @p[:client])) { |a| timed(a) }
    end

    # A picked CRM lead must exist (config.crm_find); its name fills the client.
    def with_lead(attrs)
      return yield(attrs) unless @p[:crm_ref]

      lead = HrLite.config.crm_find&.call(@p[:crm_ref])
      return "That lead was not found." unless lead

      yield(attrs.merge(crm_ref: @p[:crm_ref], client: attrs[:client] || lead[:label].to_s.truncate(120)))
    end

    def busy_attrs = timed(base)

    def out_of_office_attrs
      return "Pick a reason for being out." unless OUT_OF_OFFICE_REASONS.key?(@p[:category])

      timed(base.merge(title: OUT_OF_OFFICE_REASONS[@p[:category]]))
    end

    # One lunch a day: a fresh start can never reset the clock.
    def lunch_attrs
      day = @now.in_time_zone(HrLite.config.time_zone).all_day
      return "You have already taken lunch today." if WorkModeEvent.where(user_id: @user.id, mode: "lunch", started_at: day).exists?

      base.merge(ends_at: @now + Setting.instance.lunch_break_minutes.minutes)
    end

    def short_break_attrs = base.merge(ends_at: @now + Setting.instance.short_break_minutes.minutes)

    def parse_until
      Time.zone.parse("#{@now.to_date} #{@p[:until]}") if @p[:until]
    rescue ArgumentError
      nil
    end

    # minutes (30/60/…) or until "HH:MM" today; must be in the future, today.
    def timed(attrs, required: true)
      ends_at = @p[:minutes] ? @now + @p[:minutes].to_i.minutes : parse_until
      return attrs unless ends_at || required
      return "Pick when it ends." unless ends_at
      return "The end time must be later today." unless ends_at > @now && ends_at <= @now.end_of_day

      attrs.merge(ends_at: ends_at)
    end
  end
end
