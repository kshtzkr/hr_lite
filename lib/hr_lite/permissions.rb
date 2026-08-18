module HrLite
  # The whole vocabulary of the engine's authorization, in one place.
  #
  # A permission is a KEY plus a SCOPE. The key says what the action is
  # ("approve leave"); the scope says whose rows it reaches:
  #
  #   self  — only this person's own records
  #   team  — the people who report to them (EmployeeProfile#manager_id)
  #   all   — everyone in the company
  #
  # That is why there is no `leave.approve_own` / `leave.approve_team` /
  # `leave.approve_all` triple: one key with three possible scopes says the
  # same thing without three times the surface to get wrong.
  #
  # Keys are DATA — a role grants them from the database. They are declared
  # here so that a typo in a controller is a boot-time failure rather than a
  # permission that silently never matches.
  module Permissions
    SCOPES = %i[self team all].freeze

    # Ordered weakest to strongest. `all` satisfies a `team` requirement,
    # `team` satisfies `self`; never the other way round.
    SCOPE_RANK = { self: 0, team: 1, all: 2 }.freeze

    # key => [ group, description ]. The group is what the roles screen
    # renders as a heading; the description is the sentence beside the
    # checkbox, so it is written for the person granting it.
    REGISTRY = {
      "profile.view" => [ "People", "See employee profiles" ],
      "profile.manage" => [ "People", "Create and edit employee profiles, onboard and offboard" ],
      "attendance.view" => [ "Attendance", "See attendance records" ],
      "attendance.manage" => [ "Attendance", "Correct punches and decide regularization tickets" ],
      "leave.request" => [ "Leave", "Apply for leave and comp-off" ],
      "leave.view" => [ "Leave", "See leave requests and balances" ],
      "leave.approve" => [ "Leave", "Approve, reject and cancel leave and comp-off" ],
      "leave.manage" => [ "Leave", "Adjust balances, configure leave types and holidays" ],
      "payroll.view" => [ "Payroll", "See payroll runs and salary slips" ],
      "payroll.manage" => [ "Payroll", "Create, compute, finalize, unlock and publish payroll" ],
      "payroll.export" => [ "Payroll", "Download the payout register, including bank details" ],
      "salary.view" => [ "Payroll", "See salary structures" ],
      "salary.manage" => [ "Payroll", "Set and revise salary structures" ],
      "appraisal.view" => [ "Growth", "See appraisals" ],
      "appraisal.manage" => [ "Growth", "Write, share and act on appraisals and promotions" ],
      "resignation.view" => [ "Lifecycle", "See resignations" ],
      "resignation.manage" => [ "Lifecycle", "Accept resignations and set the last working day" ],
      "document.view" => [ "Documents", "Open other people's documents" ],
      "document.manage" => [ "Documents", "Upload, verify and open identity and bank documents" ],
      "tax.view" => [ "Payroll", "See tax declarations" ],
      "tax.manage" => [ "Payroll", "Verify tax declarations and the proof behind them" ],
      "expense.claim" => [ "Expenses", "Claim expenses" ],
      "expense.approve" => [ "Expenses", "Approve and reject expense claims" ],
      "expense.reimburse" => [ "Expenses", "Mark claims reimbursed with a payroll month" ],
      "benefit.view" => [ "Benefits", "See benefits and who is enrolled" ],
      "benefit.manage" => [ "Benefits", "Add benefits and enrol people" ],
      "hr_request.raise" => [ "Help desk", "Raise a request with HR" ],
      "hr_request.manage" => [ "Help desk", "Answer and assign HR requests" ],
      "policy.view" => [ "Policies", "Read published policies" ],
      "policy.manage" => [ "Policies", "Write, publish and re-issue policies" ],
      "settings.manage" => [ "Administration", "Change company settings, offices and policy" ],
      "audit.view" => [ "Administration", "Read the audit trail" ],
      "audit.view_money" => [ "Administration", "Read audit rows about pay, appraisals and promotions" ],
      "role.manage" => [ "Administration", "Create roles and grant permissions" ]
    }.freeze

    KEYS = REGISTRY.keys.freeze

    def self.valid?(key) = REGISTRY.key?(key.to_s)

    # Raises rather than returning false: an unknown key in a controller is a
    # typo that would otherwise read as "nobody may do this", which fails in
    # the safe direction but silently, and is then very hard to find.
    def self.validate!(key)
      return key.to_s if valid?(key)

      raise ArgumentError, "Unknown HrLite permission #{key.inspect}. " \
                           "Declare it in HrLite::Permissions::REGISTRY first."
    end

    def self.group(key) = REGISTRY.fetch(key.to_s).first
    def self.description(key) = REGISTRY.fetch(key.to_s).last

    def self.grouped
      REGISTRY.group_by { |_key, (group, _)| group }
              .transform_values { |pairs| pairs.map(&:first) }
    end

    # Does `held` satisfy a requirement for `needed`?
    def self.scope_covers?(held, needed)
      SCOPE_RANK.fetch(held.to_sym) >= SCOPE_RANK.fetch(needed.to_sym)
    end
  end
end
