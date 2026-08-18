namespace :hr_lite do
  desc "Idempotently seed HR reference data (leave types, national holidays, roles)"
  task seed: :environment do
    require "hr_lite/seeds"
    require "hr_lite/role_seeds"
    require "hr_lite/statutory_seeds"
    created = HrLite::Seeds.run! + HrLite::RoleSeeds.call + HrLite::StatutorySeeds.call
    puts created.any? ? "hr_lite:seed created: #{created.join(', ')}" : "hr_lite:seed — nothing to do"
  end

  desc "Copy the shipped statutory figures into the rate-card tables (never overwrites)"
  task statutory: :environment do
    require "hr_lite/statutory_seeds"
    created = HrLite::StatutorySeeds.call
    puts created.any? ? "hr_lite:statutory created: #{created.join(', ')}" : "hr_lite:statutory — nothing to do"
  end

  desc "Idempotently seed the built-in roles only (never overwrites a tuned role)"
  task roles: :environment do
    require "hr_lite/role_seeds"
    created = HrLite::RoleSeeds.call
    puts created.any? ? "hr_lite:roles created: #{created.join(', ')}" : "hr_lite:roles — nothing to do"
  end
end
