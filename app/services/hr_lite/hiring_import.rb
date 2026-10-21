module HrLite
  # Reads a university's candidate sheet into a preview, then imports it.
  # Headers match an alias list after case-folding and dropping punctuation
  # and spaces. A column nobody recognises is kept in `extra`, never dropped;
  # two columns claiming one field wait for HR to pick one.
  class HiringImport
    ALIASES = {
      "name" => %w[studentname name candidatename fullname],
      "email" => %w[emailid email emailaddress mailid],
      "phone" => %w[contactno contactnumber phone phoneno mobile mobileno],
      "date_of_birth" => %w[dob dobddmmyyyy dateofbirth],
      "campus" => %w[campus college],
      "course" => %w[coursepursuing course programme program],
      "branch" => %w[branchspecialization branch specialization],
      "cv_url" => %w[linkforcv cv cvlink resume resumelink]
    }.freeze

    Column = Data.define(:index, :header, :field, :extra_key)
    Row = Data.define(:number, :attributes, :extra, :outcome, :reason)

    def self.normalize(header) = header.to_s.downcase.gsub(/[^a-z0-9]/, "")

    # Cell values arrive as the sheet stored them: never evaluated, never fetched.
    def self.text(value)
      case value
      when nil then ""
      when Float then value == value.floor ? value.to_i.to_s : value.to_s
      when Date, Time then value.strftime("%d/%m/%Y")
      else value.to_s.strip
      end
    end

    attr_reader :columns, :conflicts, :rows

    # rows: arrays of cell values, headers first. picks: { "phone" => "3" }
    # names the column that wins a field two columns claim.
    def initialize(campaign, rows, picks: {})
      @campaign = campaign
      header, *body = rows
      map_columns(Array(header), picks.to_h.transform_values(&:to_i))
      @rows = classify(body)
    end

    def counts = %w[create update skip].index_with { |outcome| rows.count { |row| row.outcome == outcome } }

    def import!
      return false if conflicts.any?

      HiringCandidate.transaction do
        rows.reject { |row| row.outcome == "skip" }.each do |row|
          candidate = @campaign.candidates.find_or_initialize_by(email: row.attributes["email"])
          created = candidate.new_record?
          candidate.assign_attributes(row.attributes.merge("extra" => candidate.extra.to_h.merge(row.extra)))
          candidate.save!
          candidate.log!(created ? "imported" : "reimported") if created || candidate.saved_changes.any?
        end
      end
      true
    end

    private

    def map_columns(header, picks)
      @columns = header.each_with_index.map do |cell, index|
        field = ALIASES.find { |_, names| names.include?(self.class.normalize(cell)) }&.first
        Column.new(index:, header: cell.to_s.strip, field:, extra_key: nil)
      end
      claimed = @columns.select(&:field).group_by(&:field)
      @conflicts = claimed.select { |field, cols| cols.size > 1 && cols.none? { |c| c.index == picks[field] } }
      # A column that lost its field (or is unknown) keeps its data in `extra`.
      taken = HiringMerge::RESERVED + ALIASES.keys
      @columns = @columns.map do |col|
        loses = col.field && claimed[col.field].size > 1 && picks[col.field] != col.index
        next col if col.field && !loses

        key = col.header.parameterize(separator: "_").presence || "column_#{col.index + 1}"
        key = "sheet_#{key}" if taken.include?(key) || !key.match?(/\A[a-z]/) # @placeholders start with a letter
        taken << key
        col.with(field: nil, extra_key: key)
      end
    end

    def classify(body)
      seen = {}
      existing = @campaign.candidates.pluck(:email).to_set
      body.each_with_index.filter_map do |cells, i|
        number = i + 2 # sheet row, counting the header
        values = @columns.to_h { |col| [ col, self.class.text(Array(cells)[col.index]) ] }
        next if values.values.all?(&:blank?) # an empty row in the sheet is not a candidate

        attributes = values.select { |col, _| col.field }.to_h { |col, v| [ col.field, v.presence ] }
        attributes["email"] = attributes["email"].to_s.strip.downcase.presence
        extra = values.select { |col, v| col.extra_key && v.present? }.to_h { |col, v| [ col.extra_key, v ] }
        outcome, reason =
          if attributes["name"].blank? then [ "skip", "no name" ]
          elsif attributes["email"].blank? then [ "skip", "no email address" ]
          elsif !attributes["email"].match?(URI::MailTo::EMAIL_REGEXP) then [ "skip", "email address looks wrong" ]
          elsif seen[attributes["email"]] then [ "skip", "same email as row #{seen[attributes['email']]}" ]
          else [ existing.include?(attributes["email"]) ? "update" : "create", nil ]
          end
        seen[attributes["email"]] ||= number if attributes["email"]
        Row.new(number:, attributes:, extra:, outcome:, reason:)
      end
    end
  end
end
