module HrLite
  # One check-in or check-out as it happened. Append-only: checking in again,
  # a repeat check-out or an HR reset changes the day record, never these.
  class AttendancePunch < ApplicationRecord
    belongs_to :user, class_name: HrLite.config.user_class

    validates :kind, inclusion: { in: %w[in out] }

    def readonly? = persisted?

    # "In 09:30 Office" — the day's punches read as one line.
    def to_s = [ kind == "in" ? "In" : "Out", at.strftime("%H:%M"), AttendanceRecord::PLACES[place] ].compact.join(" ")
  end
end
