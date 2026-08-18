module HrLite
  # A laptop, a phone, a SIM. An asset nobody tracks is a cost nobody
  # notices, and the moment it matters is somebody's last day.
  class Asset < ApplicationRecord
    include Audited

    STATUSES = %w[available assigned returned lost damaged retired].freeze
    CATEGORIES = %w[laptop phone sim id_card accessory vehicle other].freeze

    has_many :asset_assignments, class_name: "HrLite::AssetAssignment", dependent: :destroy

    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :category, inclusion: { in: CATEGORIES }
    validates :serial_number, uniqueness: { allow_blank: true }

    scope :available, -> { where(status: "available") }
    scope :out, -> { where(status: "assigned") }

    STATUSES.each { |s| define_method("#{s}?") { status == s } }

    def live_assignment = asset_assignments.find_by(returned_on: nil)

    def holder = live_assignment&.user

    def assign_to!(user, actor: nil, on: Date.current)
      raise ActiveRecord::RecordInvalid.new(self), "already assigned" if live_assignment

      transaction do
        asset_assignments.create!(user_id: user.id, assigned_on: on, assigned_by_id: actor&.id)
        update!(status: "assigned")
      end
      true
    end

    # `condition` records what came back — "screen cracked" is the difference
    # between an asset returned and an asset written off.
    def return!(actor: nil, on: Date.current, condition: nil, status: "available")
      assignment = live_assignment
      raise ActiveRecord::RecordInvalid.new(self), "not assigned" if assignment.nil?

      transaction do
        assignment.update!(returned_on: on, condition_note: condition.presence)
        update!(status: status)
      end
      true
    end

    # Everything still out with somebody who has left — the report that
    # should exist before an exit, not after.
    def self.outstanding_for(user)
      joins(:asset_assignments)
        .where(hr_lite_asset_assignments: { user_id: user.id, returned_on: nil })
        .distinct
    end
  end
end
