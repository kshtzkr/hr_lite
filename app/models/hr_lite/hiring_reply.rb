module HrLite
  # A candidate's reply link for one interview round (@round1_link … @round3_link):
  # the day and 2-hour slot they can do, an optional alternate phone, round 1's
  # interest questions, and from round 2 their documents. One reply per link.
  class HiringReply < ApplicationRecord
    SLOTS = { "10-12" => "10 AM – 12 PM", "12-2" => "12 – 2 PM", "2-4" => "2 – 4 PM", "4-6" => "4 – 6 PM", "6-8" => "6 – 8 PM" }.freeze
    SLOT_START = { "10-12" => "10:00", "12-2" => "12:00", "2-4" => "14:00", "4-6" => "16:00", "6-8" => "18:00" }.freeze
    SLOT_CAPACITY = 1 # like Calendly: a booked slot on a day is gone for everyone else
    JOINING = { "immediately" => "Immediately", "two_weeks" => "Within 2 weeks", "one_month" => "Within a month" }.freeze
    YES_NO = { "stipend_ok" => "Fine with the stipend", "location_ok" => "Fine with the office location",
               "schedule_ok" => "Fine with the schedule", "programme_ok" => "Commits to the programme" }.freeze
    DOCUMENTS = { 2 => { "cv" => "CV", "photo_id" => "Photo ID" },
                  3 => { "marksheets" => "Marksheets", "aadhaar" => "Aadhaar card", "pan" => "PAN card",
                         "salary_slip_1" => "Salary slip (last month)", "salary_slip_2" => "Salary slip (2 months ago)",
                         "salary_slip_3" => "Salary slip (3 months ago)" } }.freeze
    PAN_FORMAT = /\A[A-Z]{5}[0-9]{4}[A-Z]\z/
    # Verhoeff tables, for the Aadhaar check digit.
    VERHOEFF_D = [ [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ], [ 1, 2, 3, 4, 0, 6, 7, 8, 9, 5 ], [ 2, 3, 4, 0, 1, 7, 8, 9, 5, 6 ],
                   [ 3, 4, 0, 1, 2, 8, 9, 5, 6, 7 ], [ 4, 0, 1, 2, 3, 9, 5, 6, 7, 8 ], [ 5, 9, 8, 7, 6, 0, 4, 3, 2, 1 ],
                   [ 6, 5, 9, 8, 7, 1, 0, 4, 3, 2 ], [ 7, 6, 5, 9, 8, 2, 1, 0, 4, 3 ], [ 8, 7, 6, 5, 9, 3, 2, 1, 0, 4 ],
                   [ 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 ] ].freeze
    VERHOEFF_P = [ [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ], [ 1, 5, 7, 6, 2, 8, 3, 0, 9, 4 ], [ 5, 8, 0, 3, 7, 9, 6, 1, 4, 2 ],
                   [ 8, 9, 1, 6, 0, 4, 3, 5, 2, 7 ], [ 9, 4, 5, 3, 1, 2, 6, 8, 7, 0 ], [ 4, 2, 8, 6, 5, 7, 3, 9, 0, 1 ],
                   [ 2, 7, 9, 3, 8, 0, 6, 4, 1, 5 ], [ 7, 0, 4, 6, 9, 1, 3, 2, 5, 8 ] ].freeze
    DOCUMENT_TYPES = %w[application/pdf image/jpeg image/png].freeze
    DOCUMENT_MAX = 5.megabytes

    belongs_to :candidate, class_name: "HrLite::HiringCandidate", inverse_of: :replies
    has_many_attached :documents
    encrypts :alternate_phone, :aadhaar_number, :pan_number
    has_secure_token :token, length: 24

    validates :round, inclusion: { in: 1..3 }

    scope :responded, -> { where.not(responded_at: nil) }

    def self.slot_full?(date, slot) = responded.where(preferred_date: date, preferred_slot: slot).count >= SLOT_CAPACITY

    # The slots still free on each offered day, for the reply form.
    def self.open_slots(allow_sunday:)
      days = dates(allow_sunday: allow_sunday)
      booked = responded.where(preferred_date: days).group(:preferred_date, :preferred_slot).count
      days.to_h { |day| [ day, SLOTS.keys.reject { |slot| booked[[ day, slot ]].to_i >= SLOT_CAPACITY } ] }
    end

    # The next ten interview days. Sunday is off unless the campaign allows it.
    def self.dates(allow_sunday:, from: Date.current) = (1..20).map { |i| from + i }.reject { |d| d.sunday? && !allow_sunday }.first(10)

    def self.aadhaar_valid?(number)
      number.to_s.match?(/\A[2-9]\d{11}\z/) &&
        number.reverse.chars.each_with_index.reduce(0) { |c, (digit, i)| VERHOEFF_D[c][VERHOEFF_P[i % 8][digit.to_i]] }.zero?
    end

    # What this round asks for; round 3 skips PAN and slips the candidate says they lack.
    def documents_asked
      asked = DOCUMENTS.fetch(round, {})
      asked = asked.except("pan") if pan_pending
      asked = asked.except("salary_slip_1", "salary_slip_2", "salary_slip_3") if no_salary_slips
      asked
    end

    def masked_aadhaar = aadhaar_number && "XXXX XXXX #{aadhaar_number.last(4)}"
    def masked_pan = pan_number && "XXXXX#{pan_number[5, 4]}X"

    # Documents are stored encrypted; this is the only way back to the bytes.
    def read_document(attachment) = ActiveRecord::Encryption.encryptor.decrypt(attachment.download)
    def document_label(attachment) = documents_asked[attachment.filename.to_s.split("--").first] || "Document"

    # Saves the reply, moves round 1's candidate to interested / not interested,
    # puts it on their timeline and rings the HR person who emailed them.
    def submit!(interested: nil, date: nil, slot: nil, joining: nil, yes_no: {}, alternate_phone: nil, files: {}, kyc: {})
      raise ArgumentError, "You have already replied. Thank you." if responded_at

      assign_kyc!(kyc) if round == 3

      declined = round == 1 && interested == "no"
      raise ArgumentError, "Tell us whether you want to go ahead." if round == 1 && !%w[yes no].include?(interested)

      answers = round == 1 ? { "interested" => interested } : {}
      unless declined
        date = self.class.dates(allow_sunday: candidate.campaign.allow_sunday).find { |day| day.iso8601 == date.to_s }
        raise ArgumentError, "Pick a day for the interview." unless date
        raise ArgumentError, "Pick a time slot." unless SLOTS.key?(slot)
        raise ArgumentError, "Someone just booked that slot. Pick another one." if self.class.slot_full?(date, slot)
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
          # Encrypted before it reaches storage: a leaked blob is ciphertext.
          cipher = ActiveRecord::Encryption.encryptor.encrypt(file.tempfile.read.b)
          documents.attach(io: StringIO.new(cipher), filename: "#{kind}--#{file.original_filename}", content_type: "application/octet-stream",
                           identify: false)
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

    # Round 3's joining KYC. Errors name the field, never the number.
    def assign_kyc!(kyc)
      raise ArgumentError, "Tick the consent box to share your documents." unless kyc[:consent] == "1"

      aadhaar = kyc[:aadhaar_number].to_s.gsub(/\s/, "")
      raise ArgumentError, "That Aadhaar number does not look right." unless self.class.aadhaar_valid?(aadhaar)

      self.pan_pending = kyc[:pan_pending] == "1"
      pan = kyc[:pan_number].to_s.strip.upcase
      raise ArgumentError, "That PAN does not look right." unless pan_pending || pan.match?(PAN_FORMAT)

      self.no_salary_slips = kyc[:no_salary_slips] == "1"
      self.aadhaar_number = aadhaar
      self.pan_number = (pan unless pan_pending)
    end

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
