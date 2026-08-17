namespace :hr_lite do
  desc "Idempotently seed HR reference data (leave types, national holidays, roles)"
  task seed: :environment do
    require "hr_lite/seeds"
    require "hr_lite/role_seeds"
    created = HrLite::Seeds.run! + HrLite::RoleSeeds.call
    puts created.any? ? "hr_lite:seed created: #{created.join(', ')}" : "hr_lite:seed — nothing to do"
  end

  desc "Idempotently seed the built-in roles only (never overwrites a tuned role)"
  task roles: :environment do
    require "hr_lite/role_seeds"
    created = HrLite::RoleSeeds.call
    puts created.any? ? "hr_lite:roles created: #{created.join(', ')}" : "hr_lite:roles — nothing to do"
  end
end
