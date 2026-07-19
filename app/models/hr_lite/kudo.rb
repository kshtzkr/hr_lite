module HrLite
  class Kudo < ApplicationRecord
    belongs_to :giver, class_name: HrLite.config.user_class
    has_many :kudo_mentions, dependent: :destroy
    has_many :mentioned_users, through: :kudo_mentions, source: :user

    # Text-labelled badges (rendered with an inline SVG icon, never emoji).
    BADGES = {
      "team_player"      => "Team player",
      "above_and_beyond" => "Going above and beyond",
      "customer_hero"    => "Customer hero",
      "problem_solver"   => "Problem solver",
      "culture_champion" => "Culture champion"
    }.freeze

    DELETE_WINDOW = 15.minutes

    validates :message, presence: true, length: { maximum: 1000 }
    validates :badge, inclusion: { in: BADGES.keys }, allow_blank: true

    scope :recent, -> { order(created_at: :desc, id: :desc) }

    # Praise is immutable; the giver gets a short window to undo a mistake,
    # admins/leadership can moderate any time.
    def deletable_by?(user)
      return false if user.nil?
      return true if HrLite.admin?(user) || HrLite.leadership?(user)

      giver_id == user.id && created_at > DELETE_WINDOW.ago
    end

    def badge_label
      BADGES[badge]
    end

    # Creates mention rows from the message markers (existing users only,
    # giver excluded) and notifies them. Called once, right after create.
    def register_mentions!
      ids = HrLite::MentionParser.user_ids(message) - [ giver_id ]
      users = HrLite.user_klass.where(id: ids)
      users.each { |u| kudo_mentions.create!(user_id: u.id) }

      HrLite::Notifications.publish(
        "kudos.mentioned",
        title: "#{HrLite.display_name(giver)} gave you kudos",
        body: HrLite::MentionParser.strip_markers(message).truncate(140),
        path: "/kudos",
        bell_to: users.to_a,
        email_to: users.to_a
      )
      users
    end
  end
end
