module HrLite
  class LeaveType < ApplicationRecord
    include Audited

    ACCRUALS = %w[yearly_upfront monthly].freeze

    has_many :leave_requests, dependent: :restrict_with_error
    has_many :leave_balances, dependent: :restrict_with_error

    validates :name, :code, presence: true, uniqueness: true
    validates :color, format: { with: /\A#\h{6}\z/ }
    validates :accrual, inclusion: { in: ACCRUALS }
    validates :annual_quota, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :carry_forward_cap, numericality: { greater_than_or_equal_to: 0 }

    scope :active, -> { where(active: true).order(:position, :id) }

    # The type approved comp-off requests credit into (Settings marks it).
    def self.comp_off_type
      active.find_by(comp_off: true)
    end

    def unlimited?
      annual_quota.nil?
    end
  end
end
