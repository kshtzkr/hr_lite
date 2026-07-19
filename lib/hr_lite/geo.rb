module HrLite
  # Pure-Ruby haversine — no geocoding gem needed to answer "how far is
  # this punch from the office?" at office-radius precision.
  module Geo
    EARTH_RADIUS_M = 6_371_000.0

    def self.distance_m(lat1, lng1, lat2, lng2)
      rlat1 = deg2rad(lat1)
      rlat2 = deg2rad(lat2)
      dlat = deg2rad(lat2.to_f - lat1.to_f)
      dlng = deg2rad(lng2.to_f - lng1.to_f)

      a = Math.sin(dlat / 2)**2 + Math.cos(rlat1) * Math.cos(rlat2) * Math.sin(dlng / 2)**2
      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
      EARTH_RADIUS_M * c
    end

    def self.deg2rad(deg)
      deg.to_f * Math::PI / 180
    end
  end
end
