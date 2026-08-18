module HrLite
  # What an employee claims for the year, section by section, replacing the
  # single `declared_annual_deductions` figure an admin used to type in.
  #
  # The whole year's TDS is projected from this number, so it matters that it
  # is broken down, that the employee submitted it themselves, and that HR
  # can record what the proof actually supported.
  class TaxDeclaration < ApplicationRecord
    include Audited

    STATUSES = %w[draft submitted verified rejected].freeze
    REGIMES = %w[new old].freeze

    # inverse_of is load-bearing, not decoration: the foreign key is not
    # derived from the class name, so without it a nested item on an UNSAVED
    # declaration cannot see its parent and fails "declaration must exist".
    has_many :tax_declaration_items, -> { order(:section) },
             class_name: "HrLite::TaxDeclarationItem", inverse_of: :declaration,
             foreign_key: :declaration_id, dependent: :destroy
    accepts_nested_attributes_for :tax_declaration_items, allow_destroy: true

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :verified_by, class_name: HrLite.config.user_class, optional: true

    validates :status, inclusion: { in: STATUSES }
    validates :regime, inclusion: { in: REGIMES }
    validates :financial_year, presence: true, uniqueness: { scope: :user_id }
    validate :financial_year_opens_in_april

    STATUSES.each { |s| define_method("#{s}?") { status == s } }

    def self.for(user, period_month)
      find_by(user_id: user.id, financial_year: FinancialYear.start_for(period_month))
    end

    def label = "FY #{FinancialYear.label(financial_year)}"

    def declared_total = tax_declaration_items.sum(BigDecimal(0)) { |i| i.declared_amount || 0 }

    # What payroll should actually deduct against. Until HR has verified it,
    # the declared figure stands — asking somebody to overpay tax all year
    # because paperwork is slow is its own kind of wrong — but once verified,
    # only what the proof supported counts.
    def allowable_total
      return declared_total unless verified?

      tax_declaration_items.sum(BigDecimal(0)) { |i| i.verified_amount || BigDecimal(0) }
    end

    def submit!(actor:)
      raise ActiveRecord::RecordInvalid.new(self), "not a draft" unless draft? || rejected?

      update!(status: "submitted", submitted_at: Time.current)
      Notifications.publish(
        "tax.declaration_submitted",
        title: "#{HrLite.display_name(user)} submitted a #{label} tax declaration",
        path: "/admin/tax_declarations/#{id}",
        bell_to: HrLite.users_holding("tax.manage").to_a
      )
      true
    end

    def verify!(actor:, note: nil)
      raise ActiveRecord::RecordInvalid.new(self), "not submitted" unless submitted?

      update!(status: "verified", verified_by_id: actor.id, verified_at: Time.current,
              note: note.presence)
      notify_employee("Your #{label} tax declaration was verified")
      true
    end

    def reject!(actor:, note:)
      raise ArgumentError, "a rejection needs a reason" if note.blank?

      update!(status: "rejected", verified_by_id: actor.id, verified_at: Time.current, note: note)
      notify_employee("Your #{label} tax declaration needs attention")
      true
    end

    private

    def notify_employee(title)
      Notifications.publish(
        "tax.declaration_decided", title: title, body: note.presence,
        path: "/tax_declaration", bell_to: [ user ], email_to: [ user ]
      )
    end

    def financial_year_opens_in_april
      return if financial_year.blank?
      return if financial_year == FinancialYear.start_for(financial_year)

      errors.add(:financial_year, "must be 1 April — a declaration covers a whole year")
    end
  end
end
