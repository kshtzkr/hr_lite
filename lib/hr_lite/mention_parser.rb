module HrLite
  # Kudos messages carry mentions as visible plain-text markers:
  #   "Great save @[Asha Rao](42) during the outage"
  # The picker inserts them; this parser extracts the ids server-side.
  module MentionParser
    MARKER = /@\[([^\]\n]{1,80})\]\((\d+)\)/
    LIMIT = 10 # notification-spam cap

    def self.user_ids(text)
      text.to_s.scan(MARKER).map { |(_name, id)| id.to_i }.uniq.first(LIMIT)
    end

    # Bell/email bodies show "@Asha Rao", never the raw marker.
    def self.strip_markers(text)
      text.to_s.gsub(MARKER) { "@#{Regexp.last_match(1)}" }
    end
  end
end
