module HrLite
  class Holiday < ApplicationRecord
    include Audited

    belongs_to :office_location, optional: true

    validates :date, presence: true, uniqueness: { scope: :office_location_id }
    validates :name, presence: true

    scope :company_wide, -> { where(optional: false) }
    scope :in_range, ->(range) { where(date: range) }
    scope :upcoming, -> { where(date: Date.current..).order(:date) }

    scope :for_office, ->(office_id) { where(office_location_id: [ nil, office_id ].uniq) }

    # Days off for one office: every all-office holiday plus that office's
    # own. Optional holidays never exclude working days.
    def self.dates_for(range, office_id = nil)
      company_wide.in_range(range).for_office(office_id).pluck(:date).to_set
    end

    def office_label = office_location&.name || "All offices"
  end
end
