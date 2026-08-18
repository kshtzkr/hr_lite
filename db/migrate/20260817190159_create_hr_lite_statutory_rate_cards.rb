class CreateHrLiteStatutoryRateCards < ActiveRecord::Migration[8.1]
  # Statutory rates lived in a frozen hash in Ruby, so adding a financial year
  # meant a gem release. Every April that is a deadline the gem controls and
  # the company does not — and 0.5.3 shipped a warning about exactly that
  # because the FY2026-27 card did not exist.
  #
  # Rates are not secret (they are published by the government), so the
  # figures are plain JSON. What matters is that they are EFFECTIVE-DATED and
  # carry who checked them: a payroll rerun of an old month must resolve to
  # the card that was in force for that month, not to today's.
  def change
    create_table :hr_lite_statutory_rate_cards do |t|
      t.date :effective_from, null: false
      t.json :pf, null: false, default: {}
      t.json :esi, null: false, default: {}
      t.json :income_tax, null: false, default: {}
      # Who signed it off, and when. A card nobody has confirmed is a card
      # payroll should say something about — see SlipBuilder's warnings.
      t.string :verified_by
      t.date :verified_on
      t.text :notes
      t.timestamps
    end
    # One card per date: two would make "which rates applied in June" a
    # question about row order.
    add_index :hr_lite_statutory_rate_cards, :effective_from, unique: true

    create_table :hr_lite_professional_tax_slabs do |t|
      # Professional tax is a STATE levy. Karnataka was the only state with
      # real slabs in code; every other state silently computed zero, which
      # is a wrong answer delivered confidently.
      t.string :state, null: false
      t.date :effective_from, null: false
      # Inclusive lower bound on monthly earned gross.
      t.decimal :from_amount, precision: 12, scale: 2, null: false
      t.decimal :monthly, precision: 12, scale: 2, null: false
      # Several states collect a larger amount in the last month of the year.
      t.decimal :feb_extra, precision: 12, scale: 2
      t.timestamps
    end
    add_index :hr_lite_professional_tax_slabs, %i[state effective_from from_amount],
              unique: true, name: "index_hr_lite_pt_slabs_on_state_date_and_bound"
  end
end
