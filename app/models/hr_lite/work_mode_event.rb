module HrLite
  # One stretch of a work mode. Open rows (ended_at nil) are the current
  # status — at most one primary and one overlay per person; closed rows are
  # the day's timeline. Never deleted.
  class WorkModeEvent < ApplicationRecord
    # mode => [ label, layer, place shown to teammates ]
    MODES = {
      "office" => [ "In office", "primary", "Office" ],
      "wfh" => [ "Work from home", "primary", "Home" ],
      "travelling" => [ "Travelling", "primary", "Travelling" ],
      "outside_meeting" => [ "Outside office meeting", "primary", "Client meeting" ],
      "offline" => [ "Offline", "primary", nil ],
      "meeting" => [ "Meeting", "overlay", nil ],
      "lunch" => [ "Lunch break", "overlay", nil ],
      "short_break" => [ "Short break", "overlay", nil ],
      "busy" => [ "Busy", "overlay", nil ],
      "out_of_office" => [ "Out of office", "overlay", nil ]
    }.freeze
    SOURCES = %w[system employee hr].freeze
    END_REASONS = %w[switched expired ended checked_out day_closed].freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :set_by, class_name: HrLite.config.user_class, optional: true
    belongs_to :attendance_record, optional: true

    validates :mode, inclusion: { in: MODES.keys }
    validates :source, inclusion: { in: SOURCES }
    validates :end_reason, inclusion: { in: END_REASONS }, allow_nil: true
    validates :title, :client, :destination, length: { maximum: 120 }
    validate :ends_after_start

    before_validation { self.layer = MODES.dig(mode, 1) if mode }

    scope :open, -> { where(ended_at: nil) }
    scope :primary, -> { where(layer: "primary") }
    scope :overlay, -> { where(layer: "overlay") }

    def self.label(mode) = MODES.dig(mode, 0)

    # Closes the open row on the same layer and opens this one, atomically.
    def self.start!(user_id:, mode:, source:, actor: nil, at: Time.current, **attrs)
      transaction do
        layer = MODES.dig(mode, 1)
        open.where(user_id: user_id, layer: layer).lock.each { |e| e.close!("switched", at: at) }
        event = create!(user_id: user_id, mode: mode, source: source, started_at: at, set_by_id: actor&.id, **attrs)
        AuditLog.record!(action: "work_mode.#{mode}", subject: event, actor: actor || HrLite::Current.actor,
                         changes: { "source" => source, "until" => event.ends_at&.iso8601, "reason" => event.reason }.compact)
        event
      end
    end

    # Ends every open row for the person (check-out, day close).
    def self.close_all!(user_id, reason, at: Time.current)
      open.where(user_id: user_id).lock.each { |e| e.close!(reason, at: at) }
    end

    def label = self.class.label(mode)
    def place = MODES.dig(mode, 2)
    def timed? = ends_at.present?
    def expired?(now = Time.current) = ended_at.nil? && ends_at.present? && ends_at <= now

    def close!(reason, at: Time.current)
      update!(ended_at: [ at, ends_at ].compact.min, end_reason: reason)
    end

    private

    def ends_after_start
      errors.add(:ends_at, "must be after the start") if ends_at && started_at && ends_at <= started_at
    end
  end
end
