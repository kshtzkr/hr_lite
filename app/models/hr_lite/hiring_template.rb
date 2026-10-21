module HrLite
  # An email HR writes once and sends to many. @placeholders are filled per
  # candidate by HiringMerge at send time.
  class HiringTemplate < ApplicationRecord
    has_many :messages, class_name: "HrLite::HiringMessage", foreign_key: :template_id, dependent: :restrict_with_error

    validates :name, :subject, :body, presence: true

    scope :alphabetical, -> { order(:name) }
  end
end
