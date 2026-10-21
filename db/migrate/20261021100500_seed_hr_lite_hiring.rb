class SeedHrLiteHiring < ActiveRecord::Migration[8.1]
  # hiring.manage is new in 0.61.0. RoleSeeds only creates missing roles, so
  # the existing HR, Leadership and Super Admin roles get it here. Also seeds
  # the first outreach email so HR starts from the approved wording.
  BODY = <<~TEXT.freeze
    Hi @first_name,

    I hope you're doing well.

    I've gone through your profile and CV, and I believe your experience could be a good fit for the @position position at escapes.asia

    Before proceeding with the interview process, we'd like to confirm your interest and comfort with the following details:

    Position: @position
    Programme: @programme
    Monthly Stipend: @stipend
    Full-Time CTC: @ctc, subject to performance and successful completion of the programme
    Work Location: @location
    Work Schedule: @schedule

    The programme includes structured training during the first three months, followed by performance reviews and continued hands-on experience. Progression to a full-time role is merit-based and depends on performance throughout the programme.

    Please reply to confirm your interest and availability. Once we receive your confirmation, we'll share the interview schedule and further details.

    Looking forward to hearing from you.

    Best,
    @sender_name
  TEXT

  def up
    HrLite::Role.where(name: [ "HR", "Leadership", "Super Admin" ]).find_each do |role|
      HrLite::RoleGrant.find_or_initialize_by(role: role, permission_key: "hiring.manage").update!(scope: "all")
    end
    execute <<~SQL
      INSERT INTO hr_lite_hiring_templates (name, subject, body, created_at, updated_at)
      VALUES (#{quote("Interest check")}, #{quote("@position at escapes.asia: please confirm your interest")},
              #{quote(BODY)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
  end

  def down; end
end
