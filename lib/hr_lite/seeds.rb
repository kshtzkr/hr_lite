module HrLite
  # Idempotent reference data. Hosts run it on every deploy
  # (`rake hr_lite:seed`); re-runs never overwrite operator edits.
  module Seeds
    DEFAULT_LEAVE_TYPES = [
      { code: "CL", name: "Casual leave", color: "#0ea5e9", paid: true, annual_quota: 12, accrual: "monthly", carry_forward_cap: 0, position: 1 },
      { code: "SL", name: "Sick leave", color: "#f59e0b", paid: true, annual_quota: 6, accrual: "yearly_upfront", carry_forward_cap: 0, position: 2 },
      { code: "EL", name: "Earned leave", color: "#10b981", paid: true, annual_quota: 15, accrual: "monthly", carry_forward_cap: 30, position: 3 },
      { code: "LWP", name: "Leave without pay", color: "#6b7280", paid: false, annual_quota: nil, accrual: "yearly_upfront", carry_forward_cap: 0, position: 4 },
      { code: "CO", name: "Comp off", color: "#8b5cf6", paid: true, annual_quota: 0, accrual: "yearly_upfront", carry_forward_cap: 0, position: 5, comp_off: true }
    ].freeze

    # A travel company's staff claims. "Other" takes anything else; the
    # required "What it was for" field carries the note.
    DEFAULT_EXPENSE_CATEGORIES = [
      "Local conveyance (cab, auto, metro)", "Flights and trains", "Hotel stay",
      "Meals on duty", "Client meeting and entertainment", "Site inspection and FAM trip",
      "Visa, permit and passport fees", "Fuel, tolls and parking", "Airport transfers",
      "Phone and internet", "Courier and documents", "Printing and stationery",
      "Trade fair and events", "Tips and guide payments", "Other"
    ].freeze

    def self.run!
      seed_leave_types! + seed_holidays! + seed_expense_categories!
    end

    # Only into an empty table, so renamed or removed categories stay that way.
    def self.seed_expense_categories!
      return [] if ExpenseCategory.exists?

      DEFAULT_EXPENSE_CATEGORIES.map do |name|
        ExpenseCategory.create!(name: name, receipt_required: name != "Tips and guide payments")
        "expense_category #{name}"
      end
    end

    # Deliberately NOT auto-run from run!: an operator unticking every
    # comp-off flag to disable the feature must stay disabled across
    # deploys ("re-runs never overwrite operator edits"). Pre-0.3.0
    # installs call this once from their own upgrade seed, or just tick
    # the box under Settings -> Leave types.
    def self.seed_comp_off_flag!
      return [] if LeaveType.exists?(comp_off: true)

      type = LeaveType.find_by(code: "CO")
      return [] if type.nil?

      type.update!(comp_off: true)
      [ "comp_off flag on CO" ]
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
        next if Holiday.exists?(date: date, office_location_id: nil)

        Holiday.create!(date: date, name: name)
        "holiday #{name} #{year}"
      end
    end
  end
end
