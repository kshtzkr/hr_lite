module HrLite
  # Idempotent reference data. Hosts run it on every deploy
  # (`rake hr_lite:seed`); re-runs never overwrite operator edits.
  module Seeds
    DEFAULT_LEAVE_TYPES = [
      { code: "CL", name: "Casual leave", color: "#0ea5e9", paid: true, annual_quota: 12, accrual: "monthly", carry_forward_cap: 0, position: 1 },
      { code: "SL", name: "Sick leave", color: "#f59e0b", paid: true, annual_quota: 6, accrual: "yearly_upfront", carry_forward_cap: 0, position: 2 },
      { code: "EL", name: "Earned leave", color: "#10b981", paid: true, annual_quota: 15, accrual: "monthly", carry_forward_cap: 30, position: 3 },
      { code: "LWP", name: "Leave without pay", color: "#6b7280", paid: false, annual_quota: nil, accrual: "yearly_upfront", carry_forward_cap: 0, position: 4 },
      { code: "CO", name: "Comp off", color: "#8b5cf6", paid: true, annual_quota: 0, accrual: "yearly_upfront", carry_forward_cap: 0, position: 5 }
    ].freeze

    def self.run!
      seed_leave_types! + seed_holidays!
    end

    def self.seed_leave_types!
      DEFAULT_LEAVE_TYPES.filter_map do |attrs|
        next if LeaveType.exists?(code: attrs[:code])

        LeaveType.create!(attrs)
        "leave_type #{attrs[:code]}"
      end
    end

    # Only the three fixed-date national holidays — festival dates shift
    # every year and belong to the admin bulk-paste flow.
    def self.seed_holidays!
      year = Date.current.year
      [
        [ Date.new(year, 1, 26), "Republic Day" ],
        [ Date.new(year, 8, 15), "Independence Day" ],
        [ Date.new(year, 10, 2), "Gandhi Jayanti" ]
      ].filter_map do |date, name|
        next if Holiday.exists?(date: date)

        Holiday.create!(date: date, name: name)
        "holiday #{name} #{year}"
      end
    end
  end
end
