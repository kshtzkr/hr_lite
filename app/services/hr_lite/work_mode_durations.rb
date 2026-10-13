module HrLite
  # Time spent per work mode, worked out from the mode timeline every time it
  # is asked (no cache, so a correction shows at once). A break sitting on top
  # of a work mode counts as the break only: each moment belongs to the
  # overlay if one is running, else to the primary mode. Open rows run to now,
  # or to their end time if that has already passed.
  class WorkModeDurations
    WORKING = %w[office wfh travelling outside_meeting meeting busy].freeze
    BREAKS = %w[lunch short_break].freeze
    OTHER = %w[out_of_office].freeze

    # A reporting window in the company time zone, with the bucket its charts use.
    class Period
      KINDS = %w[day week month quarter year custom].freeze
      MAX_DAYS = 366

      attr_reader :kind, :from, :to

      def self.build(kind, date, from: nil, to: nil)
        kind = KINDS.include?(kind.to_s) ? kind.to_s : "week"
        case kind
        when "day" then new(kind, date, date)
        when "week" then new(kind, date.beginning_of_week(:monday), date.end_of_week(:monday))
        when "month" then new(kind, date.beginning_of_month, date.end_of_month)
        when "quarter" then new(kind, date.beginning_of_quarter, date.end_of_quarter)
        when "year" then new(kind, date.beginning_of_year, date.end_of_year)
        else
          raise ArgumentError, "Pick a start and an end date." unless from && to
          raise ArgumentError, "The start date is after the end date." if from > to
          raise ArgumentError, "Pick at most #{MAX_DAYS} days." if (to - from).to_i + 1 > MAX_DAYS

          new(kind, from, to)
        end
      end

      # From request params: period=, date=, from=, to=. Returns [period, error].
      def self.from_params(params, today)
        date = [ parse_date(params[:date]) || today, today ].min
        [ build(params[:period], date, from: parse_date(params[:from]), to: parse_date(params[:to])), nil ]
      rescue ArgumentError => e
        [ build("week", today), e.message ]
      end

      def self.parse_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end

      def initialize(kind, from, to)
        @kind, @from, @to = kind, from, to
      end

      def bucket
        case kind
        when "day" then :hour
        when "quarter" then :week
        when "year" then :month
        when "custom" then (to - from).to_i + 1 > 62 ? :week : :day
        else :day
        end
      end

      def label
        case kind
        when "day" then from.strftime("%A %-d %B %Y")
        when "month" then from.strftime("%B %Y")
        when "quarter" then "Q#{(from.month - 1) / 3 + 1} #{from.year}"
        when "year" then from.year.to_s
        else "#{from.strftime('%-d %b %Y')} – #{to.strftime('%-d %b %Y')}"
        end
      end

      def shift(direction)
        step = { "day" => 1.day, "week" => 1.week, "month" => 1.month, "quarter" => 3.months, "year" => 1.year }[kind]
        step ? from + (direction * step) : from
      end
    end

    Segment = Struct.new(:user_id, :mode, :from, :to, :source, :event_id) do
      def seconds = to - from
    end

    Result = Struct.new(:segments, :by_mode, :by_bucket, :by_source, :attendance, :working, :breaks, :other,
                        :offline, :days_with_data, :gaps, keyword_init: true) do
      def tracked = working + breaks + other
    end

    def self.call(user_ids, period, now: Time.current) = new(Array(user_ids), period, now).call

    def initialize(user_ids, period, now)
      @ids = user_ids
      @period = period
      @now = now
      @zone = Time.find_zone!(HrLite.config.time_zone)
      @start = @zone.local(period.from.year, period.from.month, period.from.day)
      @finish = [ @zone.local(period.to.year, period.to.month, period.to.day).end_of_day, now ].min
    end

    def call
      events = @finish > @start ? overlapping_events.group_by(&:user_id) : {}
      segments = @ids.flat_map { |id| flatten(id, events.fetch(id, [])) }
      records = AttendanceRecord.where(user_id: @ids, date: @period.from..@period.to).where.not(check_in_at: nil).to_a

      by_mode = Hash.new(0)
      by_source = Hash.new(0)
      by_bucket = bucket_keys.index_with { Hash.new(0) }
      segments.each do |seg|
        by_mode[seg.mode] += seg.seconds
        by_source[seg.source] += seg.seconds unless seg.mode == "offline"
        split(seg).each { |key, secs| by_bucket[key][seg.mode] += secs if by_bucket.key?(key) }
      end

      Result.new(
        segments: segments, by_mode: by_mode, by_bucket: by_bucket, by_source: by_source,
        attendance: records.sum { |r| attended(r) },
        working: WORKING.sum { |m| by_mode[m] }, breaks: BREAKS.sum { |m| by_mode[m] },
        other: OTHER.sum { |m| by_mode[m] }, offline: by_mode["offline"],
        days_with_data: (records.map(&:date) + segments.reject { |s| s.mode == "offline" }.map { |s| s.from.in_time_zone(@zone).to_date }).to_set,
        gaps: gaps(records, segments)
      )
    end

    private

    def overlapping_events
      WorkModeEvent.where(user_id: @ids).where("started_at < ? AND (ended_at IS NULL OR ended_at > ?)", @finish, @start)
                   .order(:started_at, :id).to_a
    end

    # Each layer is a sorted, non-overlapping list (one open row per layer is
    # enforced by the database), so one sweep over the boundaries assigns
    # every slice to its overlay or its primary without counting it twice.
    def flatten(user_id, events)
      layers = events.group_by(&:layer).transform_values { |list| list.map { |e| [ clip_start(e), clip_end(e), e ] }.select { |s, f, _| f > s } }
      primaries = layers.fetch("primary", [])
      overlays = layers.fetch("overlay", [])
      points = (primaries + overlays).flat_map { |s, f, _| [ s, f ] }.uniq.sort
      pi = oi = 0
      out = []
      points.each_cons(2) do |a, b|
        pi += 1 while pi < primaries.size && primaries[pi][1] <= a
        oi += 1 while oi < overlays.size && overlays[oi][1] <= a
        event = [ overlays[oi], primaries[pi] ].compact.find { |s, f, _| s <= a && f >= b }&.last
        next unless event

        if out.last&.event_id == event.id && out.last.to == a
          out.last.to = b
        else
          out << Segment.new(user_id, event.mode, a, b, event.source, event.id)
        end
      end
      out
    end

    def clip_start(event) = [ event.started_at, @start ].max

    def clip_end(event)
      ended = event.ended_at || (event.ends_at && event.ends_at <= @now ? event.ends_at : @now)
      [ ended, @finish ].min
    end

    # Check-in to check-out; today's open punch runs to now, an older open one counts nothing.
    def attended(record)
      return record.check_out_at - record.check_in_at if record.check_out_at
      return [ @now - record.check_in_at, 0 ].max if record.date == @now.in_time_zone(@zone).to_date

      0
    end

    def bucket_keys
      days = (@period.from..[ @period.to, @now.in_time_zone(@zone).to_date ].min).to_a
      case @period.bucket
      when :hour then (0..23).to_a
      when :day then days
      when :week then days.map { |d| d.beginning_of_week(:monday) }.uniq
      when :month then days.map(&:beginning_of_month).uniq
      end
    end

    def key_for(time)
      local = time.in_time_zone(@zone)
      case @period.bucket
      when :hour then local.hour
      when :day then local.to_date
      when :week then local.to_date.beginning_of_week(:monday)
      when :month then local.to_date.beginning_of_month
      end
    end

    # Seconds of a segment per bucket, cut at hour or day boundaries.
    def split(seg)
      step = @period.bucket == :hour ? 1.hour : 1.day
      out = Hash.new(0)
      cursor = seg.from
      while cursor < seg.to
        edge = step == 1.hour ? cursor.in_time_zone(@zone).beginning_of_hour + 1.hour : cursor.in_time_zone(@zone).beginning_of_day + 1.day
        stop = [ edge, seg.to ].min
        out[key_for(cursor)] += stop - cursor
        cursor = stop
      end
      out
    end

    # What a reviewer should look at: no modes on a worked day, modes with no
    # check-in, a check-out that never happened.
    def gaps(records, segments)
      today = @now.in_time_zone(@zone).to_date
      worked = segments.reject { |s| s.mode == "offline" }.group_by { |s| [ s.user_id, s.from.in_time_zone(@zone).to_date ] }
      punched = records.index_by { |r| [ r.user_id, r.date ] }
      out = records.filter_map do |r|
        if r.check_out_at.nil? && r.date < today then [ r.user_id, r.date, "Check-out missing" ]
        elsif !worked.key?([ r.user_id, r.date ]) then [ r.user_id, r.date, "Checked in, but no work mode recorded" ]
        end
      end
      out + worked.keys.reject { |key| punched.key?(key) }.map { |id, date| [ id, date, "Work modes recorded without a check-in" ] }
    end
  end
end
