module HrLite
  # An email HR writes once and sends to many. @placeholders are filled per
  # candidate by HiringMerge at send time.
  class HiringTemplate < ApplicationRecord
    has_many :messages, class_name: "HrLite::HiringMessage", foreign_key: :template_id, dependent: :restrict_with_error

    # The emails the Selected / Rejected / On hold buttons send. One each; edited,
    # never deleted (there is no destroy), and the purpose never changes.
    PURPOSES = { "selected" => "Selected", "rejected" => "Rejected", "on_hold" => "On hold" }.freeze

    validates :name, :subject, :body, presence: true
    validates :purpose, inclusion: { in: PURPOSES.keys }, uniqueness: true, allow_nil: true
    attr_readonly :purpose

    def self.for_decision(stage) = find_by(purpose: stage)

    scope :alphabetical, -> { order(:name) }
  end
end
