module HrLite
  class AttendanceRecord < ApplicationRecord
    STATUSES = %w[present half_day].freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :regularized_by, class_name: HrLite.config.user_class, optional: true

    validates :date, presence: true, uniqueness: { scope: :user_id }
    validates :status, inclusion: { in: STATUSES }
    validate :check_out_after_check_in

    scope :for_date, ->(date) { where(date: date) }
    scope :for_month, ->(month) { where(date: month.beginning_of_month..month.end_of_month) }
    scope :flagged, -> { where(flagged: true) }
    scope :missing_checkout, -> { where.not(check_in_at: nil).where(check_out_at: nil) }

    def regularized?
      regularized_at.present?
    end

    def worked_duration
      return nil unless check_in_at && check_out_at

      check_out_at - check_in_at
    end

    def add_flag!(note)
      self.flagged = true
      self.flag_note = [ flag_note.presence, note ].compact.join("; ")
    end

    private

    def check_out_after_check_in
      return unless check_in_at && check_out_at
      return if check_out_at >= check_in_at

      errors.add(:check_out_at, "must be after check-in")
    end
  end
end
