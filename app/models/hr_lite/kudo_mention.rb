module HrLite
  class KudoMention < ApplicationRecord
    belongs_to :kudo
    belongs_to :user, class_name: HrLite.config.user_class

    validates :user_id, uniqueness: { scope: :kudo_id }
  end
end
