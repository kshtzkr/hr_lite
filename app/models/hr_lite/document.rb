module HrLite
  # An employee's document: an Aadhaar scan, a PAN, an offer letter, a
  # certificate. The FILE is the sensitive part, so visibility is a property
  # of the row and every read goes through `readable_by?`.
  class Document < ApplicationRecord
    include Audited

    VISIBILITIES = %w[self hr money].freeze
    VERIFICATIONS = %w[pending verified rejected].freeze

    # Categories the engine knows how to reason about. An install may store
    # any string; these are the ones with an opinion attached.
    SENSITIVE_CATEGORIES = %w[aadhaar pan passport bank].freeze

    # Active Storage content-sniffs via Marcel, so this checks the real bytes
    # rather than whatever the client claimed. SVG and HTML stay out — both
    # can carry script and both render in a browser.
    ALLOWED_TYPES = %w[
      application/pdf image/jpeg image/png image/heic image/webp
    ].freeze
    MAX_BYTES = 10.megabytes

    has_one_attached :file

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :verified_by, class_name: HrLite.config.user_class, optional: true
    belongs_to :uploaded_by, class_name: HrLite.config.user_class, optional: true

    validates :category, :title, presence: true
    validates :visibility, inclusion: { in: VISIBILITIES }
    validates :verification, inclusion: { in: VERIFICATIONS }
    validate :file_is_an_allowed_kind
    validate :file_is_not_too_large
    before_validation :default_visibility_from_category, on: :create

    scope :for_user, ->(user) { where(user_id: user.id) }
    scope :expiring_before, ->(date) { where.not(expires_on: nil).where(expires_on: ..date) }
    scope :recent_first, -> { order(created_at: :desc) }

    VERIFICATIONS.each { |v| define_method("#{v}?") { verification == v } }

    def expired?(on = Date.current) = expires_on.present? && expires_on < on

    # Who may open the FILE. The owner always may; beyond that it is the
    # permission the row's visibility names. A passport is not a payslip and
    # neither is HR's to browse by default.
    def readable_by?(reader)
      return false if reader.nil?
      return true if reader.id == user_id

      case visibility
      when "self" then false
      when "hr" then HrLite.reaches?(reader, "document.view", user)
      when "money" then HrLite.can?(reader, "document.manage", scope: :all)
      end
    end

    def verify!(actor:, note: nil)
      update!(verification: "verified", verified_by_id: actor.id,
              verified_at: Time.current, verification_note: note.presence)
    end

    def reject!(actor:, note:)
      raise ArgumentError, "a rejection needs a reason" if note.blank?

      update!(verification: "rejected", verified_by_id: actor.id,
              verified_at: Time.current, verification_note: note)
    end

    private

    # An Aadhaar or a bank mandate defaults to the tightest setting rather
    # than the convenient one — a default nobody thinks about is the one that
    # leaks. An explicit choice always wins, which is why the column carries
    # no default of its own.
    def default_visibility_from_category
      return if visibility.present?

      self.visibility = SENSITIVE_CATEGORIES.include?(category.to_s) ? "money" : "hr"
    end

    def file_is_an_allowed_kind
      return unless file.attached?
      return if ALLOWED_TYPES.include?(file.blob.content_type)

      errors.add(:file, "must be a PDF or an image — #{file.blob.content_type} is not accepted")
    end

    def file_is_not_too_large
      return unless file.attached? && file.blob.byte_size > MAX_BYTES

      errors.add(:file, "must be under #{MAX_BYTES / 1.megabyte} MB")
    end
  end
end
