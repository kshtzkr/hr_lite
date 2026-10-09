class SeedHrLiteFy2026RateCards < ActiveRecord::Migration[8.1]
  # Ships the FY 2026-27 card and the October 2026 EPF-ceiling card into an
  # install that already has its cards. Creates only what is missing — a card
  # an accountant already entered is never touched.
  def up
    # A fresh install gets every shipped card from `hr_lite:seed`; this is for
    # one that already seeded, where the seed would never run again.
    return unless HrLite::StatutoryRateCardRecord.exists?

    require "hr_lite/statutory_seeds"
    created = HrLite::StatutorySeeds.seed_cards!
    say "Seeded #{created.join(', ')}" if created.any?
  end

  def down; end
end
