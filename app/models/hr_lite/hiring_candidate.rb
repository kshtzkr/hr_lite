module HrLite
  # A person from a university's sheet, moving through one campaign. Every
  # change goes on their timeline (AuditLog rows whose subject is them).
  class HiringCandidate < ApplicationRecord
    STAGES = %w[imported invited interested not_interested interview selected rejected on_hold].freeze
    # Where a stage may go next. Sending moves imported → invited; scheduling moves to interview.
    MOVES = {
      "imported" => %w[invited interested not_interested],
      "invited" => %w[interested not_interested],
      "interested" => %w[interview not_interested on_hold rejected],
      "not_interested" => %w[interested],
      "interview" => %w[interview selected rejected on_hold],
      "on_hold" => %w[interview selected rejected],
      "selected" => [], "rejected" => []
    }.freeze
    REJECTION_REASONS = [ "Communication skills", "Not available for 6 months", "Location / relocation",
                          "Stipend not acceptable", "Did not attend interview", "Other" ].freeze

    belongs_to :campaign, class_name: "HrLite::HiringCampaign", inverse_of: :candidates
    has_many :messages, class_name: "HrLite::HiringMessage", foreign_key: :candidate_id, dependent: :restrict_with_error
    has_many :interviews, class_name: "HrLite::HiringInterview", foreign_key: :candidate_id, dependent: :restrict_with_error
    has_many :replies, class_name: "HrLite::HiringReply", foreign_key: :candidate_id, inverse_of: :candidate, dependent: :restrict_with_error

    encrypts :phone, :date_of_birth
    normalizes :email, with: ->(email) { email.to_s.strip.downcase }

    validates :name, presence: true
    validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { scope: :campaign_id }
    validates :stage, inclusion: { in: STAGES }

    def first_name = name.to_s.split.first
    def stage_label = stage == "interview" ? "Interview · round #{round}" : stage.humanize
    def timeline = AuditLog.where(subject_type: self.class.name, subject_id: id).includes(:actor).order(created_at: :desc, id: :desc)

    # The one door for a stage change: refuses a move the pipeline does not
    # allow, needs a listed reason to reject, and writes the timeline row.
    def move_to!(to, reason: nil, note: nil, round: self.round, actor: HrLite::Current.actor)
      raise ArgumentError, "#{stage_label} cannot move to #{to.humanize}." unless MOVES.fetch(stage).include?(to)
      raise ArgumentError, "Pick a rejection reason." if to == "rejected" && !REJECTION_REASONS.include?(reason)
      raise ArgumentError, "Write a note for “Other”." if reason == "Other" && note.blank?

      transaction do
        from = stage
        update!(stage: to, round: round, rejection_reason: (to == "rejected" ? [ reason, note.presence ].compact.join(": ") : rejection_reason))
        log!("stage", actor: actor, from: from, to: to, reason: (reason if to == "rejected"))
      end
    end

    # This round's reply link, made on first use (a template that names it).
    def reply_for(round) = replies.find_or_create_by!(round: round)

    def log!(action, actor: HrLite::Current.actor, **changes)
      AuditLog.record!(action: "hiring.#{action}", subject: self, actor: actor, changes: changes.compact)
    end
  end
end
