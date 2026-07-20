module HrLite
  # Statutory identity + employment window. PII columns are encrypted at
  # rest; masked readers feed the employee-facing view (full values render
  # only in the leadership edit form). Records are never destroyed —
  # exits are a date, payroll history is a statutory record.
  class EmployeeProfile < ApplicationRecord
    include EncryptedMoney
    include Audited

    belongs_to :user, class_name: HrLite.config.user_class
    # Reporting line (L1). Optional; the org chart treats manager-less
    # profiles as roots (founders/directors).
    belongs_to :manager, class_name: HrLite.config.user_class, optional: true

    encrypts :pan_number, :pf_uan, :esi_number, :bank_account_number, :bank_ifsc
    encrypted_money :declared_annual_deductions

    TAX_REGIMES = %w[new old].freeze

    # Onboarding-form virtuals (the controller hands them to
    # config.onboard_user; never persisted, never audited).
    attr_accessor :new_user_name, :new_user_email, :new_user_password

    before_validation :assign_employee_code, on: :create

    validates :employee_code, presence: true, uniqueness: true
    validates :user_id, uniqueness: true
    validates :date_of_joining, presence: true
    validates :tax_regime, inclusion: { in: TAX_REGIMES }
    validates :pan_number, format: { with: /\A[A-Z]{5}[0-9]{4}[A-Z]\z/, message: "is not a valid PAN" },
                           allow_blank: true
    validates :bank_ifsc, format: { with: /\A[A-Z]{4}0[A-Z0-9]{6}\z/, message: "is not a valid IFSC" },
                          allow_blank: true
    validates :pf_uan, format: { with: /\A\d{12}\z/, message: "must be 12 digits" }, allow_blank: true
    validate :exit_after_joining
    validate :manager_chain_acyclic
    validate :manager_is_active_staff, if: :manager_id_changed?

    scope :active_for, ->(month) {
      where(date_of_joining: ..month.end_of_month)
        .where("date_of_exit IS NULL OR date_of_exit >= ?", month.beginning_of_month)
    }

    def active_on?(date)
      date_of_joining <= date && (date_of_exit.nil? || date_of_exit >= date)
    end

    def employment_range_in(month)
      from = [ date_of_joining, month.beginning_of_month ].max
      to = [ date_of_exit || month.end_of_month, month.end_of_month ].min
      from <= to ? (from..to) : nil
    end

    # The manager as shown to the employee — an exited manager reads as
    # "no manager" until leadership reassigns (matches the org chart).
    def active_manager
      return nil if manager.nil?

      boss_exit = EmployeeProfile.where(user_id: manager_id).pick(:date_of_exit)
      boss_exit && boss_exit < Date.current ? nil : manager
    end

    # [L1 user, L2 user, ...] walking manager_id upward. Cycle-safe.
    def reporting_chain
      chain = []
      seen = { user_id => true }
      current = manager_id
      while current && !seen[current]
        seen[current] = true
        boss = HrLite.user_klass.find_by(id: current)
        break if boss.nil?

        chain << boss
        current = EmployeeProfile.where(user_id: boss.id).pick(:manager_id)
      end
      chain
    end

    def masked_pan
      mask_middle(pan_number)
    end

    def masked_account
      value = bank_account_number
      value.blank? ? nil : "•••• #{value.last(4)}"
    end

    def masked_uan
      mask_middle(pf_uan)
    end

    private

    # Codes are system-assigned: Settings prefix + zero-padded next number
    # (EMP001, EMP002, ...). Scans the highest existing suffix for the
    # CURRENT prefix so changing the prefix restarts a fresh sequence
    # without colliding with history.
    def assign_employee_code
      return if employee_code.present?

      prefix = Setting.instance.employee_code_prefix
      last = self.class.where("employee_code LIKE ?", "#{sanitize_sql_like(prefix)}%")
                 .pluck(:employee_code)
                 .filter_map { |code| code.delete_prefix(prefix)[/\A\d+\z/]&.to_i }
                 .max || 0
      self.employee_code = format("%s%03d", prefix, last + 1)
    end

    def sanitize_sql_like(value)
      self.class.sanitize_sql_like(value)
    end

    # A newly-assigned manager must be a real, still-employed staff member.
    def manager_is_active_staff
      return if manager_id.nil?
      return errors.add(:manager_id, "is not a staff account") if HrLite.user_klass.find_by(id: manager_id).nil?

      boss_exit = EmployeeProfile.where(user_id: manager_id).pick(:date_of_exit)
      errors.add(:manager_id, "has already exited") if boss_exit && boss_exit < Date.current
    end

    # Walking up from the proposed manager must never reach this person.
    def manager_chain_acyclic
      return if manager_id.nil?
      return errors.add(:manager_id, "cannot be yourself") if manager_id == user_id

      seen = {}
      current = manager_id
      while current
        return errors.add(:manager_id, "creates a reporting loop") if current == user_id
        break if seen[current]

        seen[current] = true
        current = EmployeeProfile.where(user_id: current).pick(:manager_id)
      end
    end

    def mask_middle(value)
      return nil if value.blank?
      return "•" * value.length if value.length <= 4

      "#{value.first(2)}#{'•' * (value.length - 4)}#{value.last(2)}"
    end

    def exit_after_joining
      return unless date_of_exit && date_of_joining
      return if date_of_exit >= date_of_joining

      errors.add(:date_of_exit, "must be after joining")
    end
  end
end
