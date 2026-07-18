module HrLite
  # Morning leadership email: who's out, what's pending, what's flagged.
  # Sends nothing on a quiet day.
  class DailyDigestJob < ActiveJob::Base
    queue_as :default

    def perform(date: Date.current)
      query = OverviewQuery.new(date: date)
      return if query.empty?

      lines = []
      query.on_leave_today.each do |request|
        lines << "On leave: #{HrLite.display_name(request.user)} — #{request.leave_type.name} (#{request.date_range_label})"
      end
      query.pending_requests.each do |request|
        lines << "Pending approval: #{HrLite.display_name(request.user)} — #{request.leave_type.name} (#{request.date_range_label})"
      end
      query.flagged_today.each do |record|
        lines << "Flagged punch: #{HrLite.display_name(record.user)} — #{record.flag_note}"
      end
      query.missing_checkout_yesterday.each do |record|
        lines << "Missing checkout yesterday: #{HrLite.display_name(record.user)}"
      end

      Notifications.publish(
        "digest.daily",
        title: "HR daily digest — #{date.strftime('%d %b %Y')}",
        lines: lines,
        path: "/admin/overview"
      )
    end
  end
end
