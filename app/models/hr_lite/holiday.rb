module HrLite
  class Holiday < ApplicationRecord
    include Audited

    validates :date, presence: true, uniqueness: true
    validates :name, presence: true

    scope :company_wide, -> { where(optional: false) }
    scope :in_range, ->(range) { where(date: range) }
    scope :upcoming, -> { where(date: Date.current..).order(:date) }

    # Company-wide holiday dates only — optional holidays never exclude
    # working days.
    def self.dates_for(range)
      company_wide.in_range(range).pluck(:date).to_set
    end
  end
end
