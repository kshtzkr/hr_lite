module HrLite
  # Copies the figures the gem ships with into the tables that own them from
  # then on. Idempotent, and it NEVER touches a card the install already has:
  # once an accountant has corrected a number, a deploy must not put the
  # gem's version back.
  #
  # Nothing here is invented. Every figure is lifted from
  # StatutoryRateCard::CARDS, which is the same hash that has always shipped.
  module StatutorySeeds
    def self.call
      seed_cards! + seed_pt_slabs!
    end

    def self.seed_cards!
      StatutoryRateCard::CARDS.filter_map do |effective_from, card|
        next if StatutoryRateCardRecord.exists?(effective_from: effective_from)

        StatutoryRateCardRecord.create!(
          effective_from: effective_from,
          pf: stringify(card[:pf]),
          esi: stringify(card[:esi]),
          income_tax: card[:income_tax].transform_values { |regime| stringify_regime(regime) },
          notes: "Shipped with hr_lite #{HrLite::VERSION}. Confirm with your " \
                 "accountant, then record who verified it."
        )
        "rate card FY #{FinancialYear.label(effective_from)}"
      end
    end

    def self.seed_pt_slabs!
      created = []
      StatutoryRateCard::CARDS.each do |effective_from, card|
        card[:pt].each do |state, slabs|
          # An empty slab list in the shipped hash meant "we know of no bands
          # for this state" — which is exactly the silence the slab table is
          # here to distinguish from a real zero. Nothing to copy.
          next if slabs.empty?
          next if ProfessionalTaxSlab.exists?(state: state, effective_from: effective_from)

          slabs.each do |slab|
            ProfessionalTaxSlab.create!(
              state: state, effective_from: effective_from,
              from_amount: slab[:from] || slab[:above],
              monthly: slab[:monthly], feb_extra: slab[:feb_extra]
            )
          end
          created << "#{state} PT slabs"
        end
      end
      created
    end

    # JSON columns take strings so a BigDecimal survives the round trip
    # intact — a float would not, and these figures decide deductions.
    def self.stringify(hash)
      hash.to_h { |key, value| [ key.to_s, value.to_s("F") ] }
    end

    def self.stringify_regime(regime)
      {
        "standard_deduction" => regime[:standard_deduction].to_s("F"),
        "rebate_cap" => regime[:rebate_cap].to_s("F"),
        "cess_rate" => regime[:cess_rate].to_s("F"),
        "marginal_relief" => !!regime[:marginal_relief],
        "slabs" => regime[:slabs].map { |from, to, rate|
          [ from.to_s("F"), to&.to_s("F"), rate.to_s("F") ]
        }
      }
    end
  end
end
