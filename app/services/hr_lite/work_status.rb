module HrLite
  # What someone is doing right now. Precedence: holiday, then full-day leave
  # (both read from their own records — no status row is ever invented), then
  # the open primary work mode with its overlay unless that has run out, then
  # weekend, then Offline. Showing a status never grants attendance.
  class WorkStatus
    DERIVED = { "holiday" => "Holiday", "on_leave" => "On leave", "sick_leave" => "Sick leave",
                "weekend" => "Weekend", "offline" => "Offline" }.freeze
    SICK_CODE = "SL".freeze

    Entry = Struct.new(:mode, :label, :source, :since, :until, :place, :event, keyword_init: true)
    Status = Struct.new(:primary, :overlay, :custom, :half_day_leave, :updated_at, keyword_init: true) do
      def available? = primary.mode.in?(%w[office wfh travelling outside_meeting]) && (overlay.nil? || overlay.mode == "meeting")
    end

    def self.for(user_id, at: Time.current) = for_users([ user_id ], at: at)[user_id]

    # When an open Busy or Meeting ends, or nil when the person is reachable.
    def self.do_not_disturb_until(user_id, at: Time.current)
      WorkModeEvent.open.overlay.where(user_id: user_id, mode: %w[busy meeting]).where("ends_at > ?", at).maximum(:ends_at)
    end

    def self.for_users(user_ids, at: Time.current)
      date = at.in_time_zone(HrLite.config.time_zone).to_date
      events = WorkModeEvent.open.where(user_id: user_ids).group_by(&:user_id)
      leaves = LeaveRequest.active_on(date).includes(:leave_type).where(user_id: user_ids).group_by(&:user_id)
      offices = EmployeeProfile.where(user_id: user_ids).pluck(:user_id, :office_location_id).to_h
      calendars = WorkingCalendar.by_office(date..date)
      user_ids.index_with { |id| build(date, at, calendars[offices[id]], events.fetch(id, []), leaves.fetch(id, [])) }
    end

    def self.build(date, at, calendar, events, leaves)
      full = leaves.find { |l| !l.half_day }
      primary_event = events.find { |e| e.layer == "primary" }
      overlay_event = events.find { |e| e.layer == "overlay" && !e.expired?(at) }

      primary =
        if calendar.holiday?(date) then derived("holiday")
        elsif full then derived(full.leave_type&.code == SICK_CODE ? "sick_leave" : "on_leave", until_at: full.end_date)
        elsif primary_event then from(primary_event)
        elsif calendar.weekend?(date) then derived("weekend")
        else derived("offline")
        end
      overlay = from(overlay_event) if overlay_event && primary.event
      custom = events.find { |e| e.layer == "status" && !e.expired?(at) }

      Status.new(primary: primary, overlay: overlay, custom: custom, half_day_leave: leaves.find(&:half_day),
                 updated_at: events.reject { |e| e.layer == "status" }.map(&:started_at).max)
    end

    def self.derived(mode, until_at: nil) = Entry.new(mode: mode, label: DERIVED[mode], source: "system", until: until_at)

    def self.from(event)
      Entry.new(mode: event.mode, label: event.label, source: event.source, since: event.started_at,
                until: event.ends_at, place: event.place, event: event)
    end

    private_class_method :build, :derived, :from
  end
end
