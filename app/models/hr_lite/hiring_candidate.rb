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
    # The 2-hour interview windows a candidate can pick on the reply page, and
    # how many candidates one window takes on one day (HR then calls to confirm).
    SLOTS = { "10-12" => "10 AM – 12 PM", "12-2" => "12 – 2 PM", "2-4" => "2 – 4 PM", "4-6" => "4 – 6 PM", "6-8" => "6 – 8 PM" }.freeze
    SLOT_START = { "10-12" => "10:00", "12-2" => "12:00", "2-4" => "14:00", "4-6" => "16:00", "6-8" => "18:00" }.freeze
    SLOT_CAPACITY = 4
    JOINING = { "immediately" => "Immediately", "two_weeks" => "Within 2 weeks", "one_month" => "Within a month" }.freeze
    YES_NO = %w[stipend_ok location_ok schedule_ok programme_ok].freeze
    REJECTION_REASONS = [ "Communication skills", "Not available for 6 months", "Location / relocation",
                          "Stipend not acceptable", "Did not attend interview", "Other" ].freeze

    belongs_to :campaign, class_name: "HrLite::HiringCampaign", inverse_of: :candidates
    has_many :messages, class_name: "HrLite::HiringMessage", foreign_key: :candidate_id, dependent: :restrict_with_error
    has_many :interviews, class_name: "HrLite::HiringInterview", foreign_key: :candidate_id, dependent: :restrict_with_error

    encrypts :phone, :date_of_birth
    has_secure_token :interest_token, length: 24
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

    def self.slot_full?(date, slot) = where(preferred_date: date, preferred_slot: slot).count >= SLOT_CAPACITY

    # The interview days offered on the reply page: the next ten weekdays.
    def self.reply_dates(from = Date.current) = (1..20).map { |i| from + i }.reject { |d| d.saturday? || d.sunday? }.first(10)

    # The reply from the candidate's own page. Interested moves them to
    # interested (or not interested) on the timeline and tells the HR person
    # who emailed them. One reply per candidate.
    def reply!(interested:, date: nil, slot: nil, joining: nil, yes_no: {})
      raise ArgumentError, "You have already replied. Thank you." if responded_at
      raise ArgumentError, "Tell us whether you want to go ahead." unless %w[yes no].include?(interested)

      answers = { "interested" => interested }
      if interested == "yes"
        date = self.class.reply_dates.find { |day| day.iso8601 == date.to_s }
        raise ArgumentError, "Pick a day for the interview." unless date
        raise ArgumentError, "Pick a time slot." unless SLOTS.key?(slot)
        raise ArgumentError, "That slot just filled up. Pick another one." if self.class.slot_full?(date, slot)
        raise ArgumentError, "Tell us how soon you can join." unless JOINING.key?(joining)

        answers.merge!("joining" => joining, **YES_NO.to_h { |key| [ key, yes_no[key] == "yes" ? "yes" : "no" ] })
      end
      transaction do
        update!(responded_at: Time.current, answers: answers, preferred_date: (date if interested == "yes"), preferred_slot: (slot if interested == "yes"))
        to = interested == "yes" ? "interested" : "not_interested"
        move_to!(to, actor: nil) if MOVES.fetch(stage).include?(to)
        log!("replied", actor: nil, interested: interested, slot: ([ date&.strftime("%-d %b"), SLOTS[slot] ].compact.join(", ") if interested == "yes"))
      end
      notify_sender
    end

    def log!(action, actor: HrLite::Current.actor, **changes)
      AuditLog.record!(action: "hiring.#{action}", subject: self, actor: actor, changes: changes.compact)
    end

    private

    # The bell for whoever sent them the email (HrLite.notify never raises).
    def notify_sender
      user = messages.where(status: "sent").order(:sent_at).last&.sent_by or return
      HrLite.notify(user: user, kind: "hiring.reply", title: "#{name} replied: #{answers['interested'] == 'yes' ? 'interested' : 'not interested'}",
                    body: campaign.title, path: "/admin/hiring_candidates/#{id}")
    end
  end
end
