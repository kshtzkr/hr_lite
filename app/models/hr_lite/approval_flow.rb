module HrLite
  # "Leave needs the manager, then HR." One active flow per subject type;
  # a type with no flow keeps whatever single-decision behaviour it had.
  class ApprovalFlow < ApplicationRecord
    include Audited

    has_many :approval_steps, -> { order(:position) },
             class_name: "HrLite::ApprovalStep", foreign_key: :flow_id, dependent: :destroy
    accepts_nested_attributes_for :approval_steps, allow_destroy: true

    validates :subject_type, :name, presence: true
    validate :subject_type_is_approvable

    scope :active, -> { where(active: true) }

    def self.for(subject_type)
      active.find_by(subject_type: subject_type.to_s)
    end

    # Subject types that have opted in. Declared rather than derived so a
    # flow cannot be pointed at a model that has no idea it is approvable.
    def self.approvable_types
      %w[
        HrLite::LeaveRequest HrLite::CompOffRequest
        HrLite::RegularizationRequest HrLite::Resignation
      ].freeze
    end

    def subject_label = subject_type.demodulize.underscore.humanize

    private

    def subject_type_is_approvable
      return if self.class.approvable_types.include?(subject_type)

      errors.add(:subject_type, "is not a type this engine can route for approval")
    end
  end
end
