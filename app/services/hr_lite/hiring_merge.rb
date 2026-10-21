module HrLite
  # Fills a hiring email's @placeholders for one candidate. Reserved names
  # (campaign, candidate, interview, sender) win over a sheet's extra columns.
  # An unknown or blank placeholder is reported, never sent as "".
  class HiringMerge
    TOKEN = /(?<![\w.@])@([a-z][a-z0-9_]*)/
    GROUPS = { "Candidate" => %w[first_name name course branch campus],
               "Offer" => %w[position programme stipend ctc location schedule],
               "Interview" => %w[interview_date interview_time meet_link sender_name],
               "Reply links" => %w[round1_link round2_link round3_link] }.freeze
    RESERVED = GROUPS.values.flatten.freeze

    Result = Data.define(:subject, :body, :missing)

    def self.tokens(text) = text.to_s.scan(TOKEN).flatten.uniq

    def initialize(candidate, sender_name:)
      @extra = candidate.extra.to_h.transform_keys(&:to_s)
      @values = @extra.merge(reserved(candidate, sender_name))
    end

    def render(template)
      missing = []
      fill = ->(text) {
        text.to_s.gsub(TOKEN) do
          key = Regexp.last_match(1)
          value = @values[key]
          value = (value.respond_to?(:call) ? value.call : value).to_s.strip
          next value unless value.empty?

          missing << "@#{key} (#{RESERVED.include?(key) || @extra.key?(key) ? 'empty' : 'unknown'})"
          Regexp.last_match(0)
        end
      }
      Result.new(subject: fill.(template.subject), body: fill.(template.body), missing: missing.uniq)
    end

    private

    def reserved(candidate, sender_name)
      campaign = candidate.campaign
      interview = candidate.interviews.where(status: "scheduled").order(:round).last
      at = interview&.starts_at&.in_time_zone(HrLite.config.time_zone)
      { "name" => candidate.name, "first_name" => candidate.first_name, "course" => candidate.course,
        "branch" => candidate.branch, "campus" => candidate.campus, "position" => campaign.position,
        "programme" => campaign.programme, "stipend" => campaign.stipend, "ctc" => campaign.ctc,
        "location" => campaign.location, "schedule" => campaign.schedule,
        "interview_date" => at&.strftime("%-d %B %Y"), "interview_time" => at&.strftime("%-l:%M %p"),
        "meet_link" => interview&.meet_link, "sender_name" => sender_name,
        # Lazy: a round's link (and its row) is made only when a template names it.
        **(1..3).to_h { |r| [ "round#{r}_link", -> { HrLite.public_url("/apply/#{candidate.reply_for(r).token}") } ] } }
    end
  end
end
