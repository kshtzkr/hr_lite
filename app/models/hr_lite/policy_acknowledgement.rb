module HrLite
  # "I have read this." Kept per VERSION, and never edited — it is the
  # evidence, and evidence that can be changed afterwards is not evidence.
  class PolicyAcknowledgement < ApplicationRecord
    belongs_to :policy, class_name: "HrLite::Policy"
    belongs_to :user, class_name: HrLite.config.user_class

    validates :acknowledged_at, presence: true
    validates :user_id, uniqueness: { scope: :policy_id }

    def readonly? = persisted?
  end
end
