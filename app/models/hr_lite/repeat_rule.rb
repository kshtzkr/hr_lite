module HrLite
  # A calendar repeat, like Google Calendar's custom repeat (an RRULE subset):
  # every N days, weeks (on chosen weekdays) or months (on the start's date),
  # from a start date, ending never, on a date, or after N times. Stored as
  # text, e.g. "FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE,FR;DTSTART=2026-10-20;COUNT=12".
  class RepeatRule
    FREQS = { "DAILY" => "day", "WEEKLY" => "week", "MONTHLY" => "month" }.freeze
    DAYS = %w[SU MO TU WE TH FR SA].freeze # index = Date#wday

    attr_reader :freq, :interval, :days, :from, :until_date, :count

    def self.parse(text)
      return if text.blank?

      parts = text.split(";").to_h { |part| part.split("=", 2) }
      new(freq: parts["FREQ"], interval: parts["INTERVAL"], days: parts["BYDAY"].to_s.split(","),
          from: parts["DTSTART"], until_date: parts["UNTIL"], count: parts["COUNT"])
    end

    # The form's repeat[...] fields; a blank frequency means every day (no rule).
    def self.from_params(params)
      return if params[:freq].blank?

      new(freq: params[:freq], interval: params[:interval], days: Array(params[:days]).compact_blank, from: params[:from],
          until_date: (params[:until] if params[:ends] == "on"), count: (params[:count] if params[:ends] == "after"))
    end

    def initialize(freq:, interval: 1, days: [], from: nil, until_date: nil, count: nil)
      @freq = FREQS.key?(freq.to_s.upcase) ? freq.to_s.upcase : "DAILY"
      @interval = [ interval.to_i, 1 ].max
      @days = days.map(&:upcase) & DAYS
      @from = to_date(from) || Date.current
      @until_date = to_date(until_date)
      @count = count.to_i.positive? ? count.to_i : nil
    end

    def to_s
      [ "FREQ=#{freq}", "INTERVAL=#{interval}", ("BYDAY=#{days.join(',')}" if days.any?), "DTSTART=#{from.iso8601}",
        ("UNTIL=#{until_date.iso8601}" if until_date), ("COUNT=#{count}" if count) ].compact.join(";")
    end

    def occurs_on?(date)
      return false if date < from || (until_date && date > until_date) || !matches?(date)

      count.nil? || (from..date).count { |day| matches?(day) } <= count
    end

    # "Every 2 weeks on Mon, Wed, Fri from 20 Oct 2026, 12 times"
    def describe
      every = interval == 1 ? "Every #{FREQS[freq]}" : "Every #{interval} #{FREQS[freq]}s"
      on = (" on #{days.map { |d| Date::ABBR_DAYNAMES[DAYS.index(d)] }.join(', ')}" if freq == "WEEKLY" && days.any?)
      ends = until_date ? ", until #{until_date.strftime('%-d %b %Y')}" : (", #{count} times" if count)
      "#{every}#{on} from #{from.strftime('%-d %b %Y')}#{ends}"
    end

    private

    def matches?(date)
      case freq
      when "DAILY" then ((date - from).to_i % interval).zero?
      when "WEEKLY"
        (days.any? ? days.include?(DAYS[date.wday]) : date.wday == from.wday) &&
          (((date.beginning_of_week - from.beginning_of_week).to_i / 7) % interval).zero?
      else date.day == from.day && (((date.year * 12) + date.month - (from.year * 12) - from.month) % interval).zero?
      end
    end

    def to_date(value)
      value.is_a?(Date) ? value : Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
