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

    # Where a punch happened, for the admin board: the office whose radius
    # covers it, else "Off-site · 3.2 km from Head Office". Nil without GPS.
    def self.place(lat, lng, offices = active.to_a)
      return if lat.nil? || lng.nil?

      office = offices.min_by { |o| Geo.distance_m(o.lat, o.lng, lat, lng) }
      return "Off-site" unless office

      metres = Geo.distance_m(office.lat, office.lng, lat, lng)
      metres <= office.radius_m ? office.name : "Off-site · #{(metres / 1000.0).round(1)} km from #{office.name}"
    end

    # For flag notes: "1.2 km from Head Office". Nil when no offices exist.
    def self.nearest(lat, lng)
      active.min_by { |office| Geo.distance_m(office.lat, office.lng, lat, lng) }
    end
  end
end
