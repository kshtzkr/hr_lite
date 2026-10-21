module HrLite
  # A candidate's reply link for one interview round (@round1_link … @round3_link):
  # the day and 2-hour slot they can do, an optional alternate phone, round 1's
  # interest questions, and from round 2 their documents. One reply per link.
  class HiringReply < ApplicationRecord
    SLOTS = { "10-12" => "10 AM – 12 PM", "12-2" => "12 – 2 PM", "2-4" => "2 – 4 PM", "4-6" => "4 – 6 PM", "6-8" => "6 – 8 PM" }.freeze
    SLOT_START = { "10-12" => "10:00", "12-2" => "12:00", "2-4" => "14:00", "4-6" => "16:00", "6-8" => "18:00" }.freeze
    SLOT_CAPACITY = 4 # candidates per slot per day; HR calls each to confirm
    JOINING = { "immediately" => "Immediately", "two_weeks" => "Within 2 weeks", "one_month" => "Within a month" }.freeze
    YES_NO = { "stipend_ok" => "Fine with the stipend", "location_ok" => "Fine with the office location",
               "schedule_ok" => "Fine with the schedule", "programme_ok" => "Commits to the programme" }.freeze
    DOCUMENTS = { 2 => { "cv" => "CV", "photo_id" => "Photo ID" },
                  3 => { "marksheets" => "Marksheets", "address_proof" => "Address proof" } }.freeze
    DOCUMENT_TYPES = %w[application/pdf image/jpeg image/png].freeze
    DOCUMENT_MAX = 5.megabytes

    belongs_to :candidate, class_name: "HrLite::HiringCandidate", inverse_of: :replies
    has_many_attached :documents
    encrypts :alternate_phone
    has_secure_token :token, length: 24

    validates :round, inclusion: { in: 1..3 }

    scope :responded, -> { where.not(responded_at: nil) }

    def self.slot_full?(date, slot) = responded.where(preferred_date: date, preferred_slot: slot).count >= SLOT_CAPACITY

    # The next ten interview days. Sunday is off unless the campaign allows it.
    def self.dates(allow_sunday:, from: Date.current) = (1..20).map { |i| from + i }.reject { |d| d.sunday? && !allow_sunday }.first(10)

    def documents_asked = DOCUMENTS.fetch(round, {})
    def document_label(attachment) = documents_asked[attachment.filename.to_s.split("--").first] || "Document"

    # Saves the reply, moves round 1's candidate to interested / not interested,
    # puts it on their timeline and rings the HR person who emailed them.
    def submit!(interested: nil, date: nil, slot: nil, joining: nil, yes_no: {}, alternate_phone: nil, files: {})
      raise ArgumentError, "You have already replied. Thank you." if responded_at

      declined = round == 1 && interested == "no"
      raise ArgumentError, "Tell us whether you want to go ahead." if round == 1 && !%w[yes no].include?(interested)

      answers = round == 1 ? { "interested" => interested } : {}
      unless declined
        date = self.class.dates(allow_sunday: candidate.campaign.allow_sunday).find { |day| day.iso8601 == date.to_s }
        raise ArgumentError, "Pick a day for the interview." unless date
        raise ArgumentError, "Pick a time slot." unless SLOTS.key?(slot)
        raise ArgumentError, "That slot just filled up. Pick another one." if self.class.slot_full?(date, slot)
        raise ArgumentError, "That phone number does not look right." if alternate_phone.present? && !alternate_phone.to_s.gsub(/[\s-]/, "").match?(/\A\+?\d{7,15}\z/)

        if round == 1
          raise ArgumentError, "Tell us how soon you can join." unless JOINING.key?(joining)

          answers.merge!("joining" => joining, **YES_NO.keys.to_h { |key| [ key, yes_no[key] == "yes" ? "yes" : "no" ] })
        end
        check_files!(files)
      end

      transaction do
        update!(responded_at: Time.current, answers: answers, alternate_phone: alternate_phone.presence,
                preferred_date: (date unless declined), preferred_slot: (slot unless declined))
        files.slice(*documents_asked.keys).each do |kind, file|
          documents.attach(io: file.tempfile, filename: "#{kind}--#{file.original_filename}", content_type: sniff(file))
        end
        if round == 1
          to = declined ? "not_interested" : "interested"
          candidate.move_to!(to, actor: nil) if HiringCandidate::MOVES.fetch(candidate.stage).include?(to)
        end
        candidate.log!("replied", actor: nil, round: round, interested: answers["interested"],
                                  slot: ([ date.strftime("%-d %b"), SLOTS[slot] ].join(", ") unless declined))
      end
      notify_sender
    end

    private

    # Every asked document, a real PDF/JPG/PNG (read from the bytes, not the
    # browser's claim), at most 5 MB.
    def check_files!(files)
      documents_asked.each do |kind, label|
        file = files[kind]
        raise ArgumentError, "Attach your #{label}." unless file.respond_to?(:original_filename)
        raise ArgumentError, "#{label} must be a PDF, JPG or PNG." unless DOCUMENT_TYPES.include?(sniff(file))
        raise ArgumentError, "#{label} must be 5 MB or smaller." if file.size > DOCUMENT_MAX
      end
    end

    def sniff(file) = Marcel::MimeType.for(file.tempfile, name: file.original_filename).tap { file.tempfile.rewind }

    def notify_sender
      user = candidate.messages.where(status: "sent").order(:sent_at).last&.sent_by or return
      HrLite.notify(user: user, kind: "hiring.reply", body: candidate.campaign.title, path: "/admin/hiring_candidates/#{candidate_id}",
                    title: "#{candidate.name} replied to round #{round}#{": #{answers['interested'] == 'yes' ? 'interested' : 'not interested'}" if round == 1}")
    end
  end
end
