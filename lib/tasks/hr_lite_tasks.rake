namespace :hr_lite do
  desc "Idempotently seed HR reference data (leave types, national holidays)"
  task seed: :environment do
    require "hr_lite/seeds"
    created = HrLite::Seeds.run!
    puts created.any? ? "hr_lite:seed created: #{created.join(', ')}" : "hr_lite:seed — nothing to do"
  end
end
