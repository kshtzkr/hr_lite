module HrLite
  # A place an employee may work from at home. Coordinates come from the
  # device at "Register here", never typed; HR approves before it counts.
  class WorkLocation < ApplicationRecord
    STATUSES = %w[pending approved rejected removed].freeze
    MAX_LIVE = 3
    FENCE_M = 500
    MAX_ACCURACY_M = FENCE_M # owner 2026-10-14: a fix good to the 500 m fence may pin a home

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :decided_by, class_name: HrLite.config.user_class, optional: true

    validates :name, presence: true, length: { maximum: 60 }
    validates :address, length: { maximum: 200 }
    validates :status, inclusion: { in: STATUSES }
    validates :lat, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
    validates :lng, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
    validates :accuracy_m, numericality: { greater_than: 0, less_than_or_equal_to: MAX_ACCURACY_M,
                                           message: "must be %{count} m or better — step outside or wait for GPS and try again" }
    validate :within_limit, on: :create

    scope :live, -> { where(status: %w[pending approved]) }
    scope :approved, -> { where(status: "approved") }
    scope :pending, -> { where(status: "pending") }

    STATUSES.each { |s| define_method("#{s}?") { status == s } }

    def self.active_for(user_id) = approved.find_by(user_id: user_id, active: true)

    def covers?(lat, lng) = Geo.distance_m(self.lat, self.lng, lat.to_f, lng.to_f) <= FENCE_M

    def map_url = "https://www.google.com/maps?q=#{lat},#{lng}"

    def decide!(status, actor:, note: nil)
      raise ActiveRecord::RecordInvalid.new(self), "not pending" unless pending?

      update!(status: status, decided_by_id: actor.id, decided_at: Time.current, decision_note: note)
      make_active! if approved? && !self.class.approved.where(user_id: user_id, active: true).exists?
      AuditLog.record!(action: "work_location.#{status}", subject: self, actor: actor, changes: { "name" => name, "note" => note }.compact)
    end

    def make_active!
      transaction do
        self.class.where(user_id: user_id, active: true).where.not(id: id).update_all(active: false)
        update!(active: true)
      end
    end

    def remove!(actor:)
      update!(status: "removed", active: false)
      AuditLog.record!(action: "work_location.removed", subject: self, actor: actor, changes: { "name" => name })
    end

    private

    def within_limit
      return unless self.class.live.where(user_id: user_id).count >= MAX_LIVE

      errors.add(:base, "You can register at most #{MAX_LIVE} locations. Remove one first.")
    end
  end
end
