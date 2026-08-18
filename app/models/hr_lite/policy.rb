module HrLite
  # A written policy people are held to. Versioned, because "you agreed to
  # this" is only true of the version somebody actually read.
  class Policy < ApplicationRecord
    include Audited

    has_many :policy_acknowledgements, class_name: "HrLite::PolicyAcknowledgement",
                                       dependent: :destroy

    validates :title, presence: true, uniqueness: { scope: :version }
    validates :body, presence: true
    validates :effective_from, presence: true
    validates :version, numericality: { greater_than: 0 }

    scope :published, -> { where(published: true) }
    scope :live_on, ->(date) { published.where(effective_from: ..date) }
    scope :newest_first, -> { order(effective_from: :desc, version: :desc) }

    # The version in force today for each title — an older one stays for the
    # acknowledgements attached to it, but nobody should be reading it.
    def self.current
      live_on(Date.current).group_by(&:title).values.map do |versions|
        versions.max_by(&:version)
      end
    end

    # Re-issuing asks everybody again, which is the whole point of versioning
    # it: an acknowledgement of v1 says nothing about v2.
    def supersede!(body:, effective_from: Date.current, acknowledgement_required: nil)
      self.class.create!(
        title: title, body: body, version: version + 1, effective_from: effective_from,
        acknowledgement_required: acknowledgement_required.nil? ? self.acknowledgement_required : acknowledgement_required,
        published: true
      )
    end

    def acknowledged_by?(user)
      policy_acknowledgements.exists?(user_id: user.id)
    end

    def outstanding_for
      return HrLite.user_klass.none unless acknowledgement_required && published

      HrLite.user_klass.where(id: HrLite.active_employees.map(&:id))
            .where.not(id: policy_acknowledgements.select(:user_id))
    end

    # Clicking twice is not an error and must not read as one. The
    # find_or_create handles the second click; the rescue handles two
    # requests arriving at once, which the unique index refuses.
    def acknowledge!(user)
      policy_acknowledgements.find_or_create_by!(user_id: user.id) do |ack|
        ack.acknowledged_at = Time.current
      end
    rescue ActiveRecord::RecordNotUnique
      policy_acknowledgements.find_by!(user_id: user.id)
    end
  end
end
