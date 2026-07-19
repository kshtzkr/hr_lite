module HrLite
  class OfficeLocation < ApplicationRecord
    include Audited

    validates :name, presence: true
    validates :lat, presence: true, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
    validates :lng, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
    validates :radius_m, presence: true, numericality: { only_integer: true, greater_than: 0 }

    scope :active, -> { where(active: true) }

    def self.covering?(lat, lng)
      active.any? { |office| Geo.distance_m(office.lat, office.lng, lat, lng) <= office.radius_m }
    end

    # For flag notes: "1.2 km from Head Office". Nil when no offices exist.
    def self.nearest(lat, lng)
      active.min_by { |office| Geo.distance_m(office.lat, office.lng, lat, lng) }
    end
  end
end
