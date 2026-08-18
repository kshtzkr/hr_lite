module HrLite
  module Admin
    # Adding a financial year, and recording who checked it. Money tier: these
    # figures decide what lands in a bank account.
    #
    # New years are created by COPYING the newest card — a year's PF and ESI
    # figures usually carry over untouched and only the slabs move, so a blank
    # form would be an invitation to mistype eight numbers that were already
    # right.
    class StatutoryRateCardsController < SuperadminController
      def index
        @cards = StatutoryRateCardRecord.chronological.reverse
        @states = ProfessionalTaxSlab.distinct.order(:state).pluck(:state)
      end

      def new
        newest = StatutoryRateCardRecord.chronological.last
        @card = StatutoryRateCardRecord.new(
          effective_from: next_financial_year(newest),
          pf: newest&.pf || {}, esi: newest&.esi || {}, income_tax: newest&.income_tax || {}
        )
        @copied_from = newest
      end

      def create
        @card = StatutoryRateCardRecord.new(card_params)
        if @card.save
          redirect_to admin_statutory_rate_cards_path,
                      notice: "FY #{@card.financial_year} card saved. Payroll will use it " \
                              "from #{@card.effective_from.strftime('%d %b %Y')}."
        else
          @copied_from = nil
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @card = StatutoryRateCardRecord.find(params[:id])
      end

      def update
        @card = StatutoryRateCardRecord.find(params[:id])
        if @card.update(card_params)
          redirect_to admin_statutory_rate_cards_path, notice: "FY #{@card.financial_year} card updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def next_financial_year(newest)
        return FinancialYear.start_for(Date.current) if newest.nil?

        [ newest.effective_from.next_year, FinancialYear.start_for(Date.current) ].max
      end

      # The figures arrive as flat strings from number fields and are stored
      # as strings in JSON — a float would not survive the round trip intact,
      # and these decide deductions.
      def card_params
        permitted = params.require(:statutory_rate_card)
                          .permit(:effective_from, :verified_by, :verified_on, :notes,
                                  pf: {}, esi: {}, income_tax: {})
        permitted.to_h.tap do |attrs|
          attrs["income_tax"] = rebuild_regimes(attrs["income_tax"]) if attrs["income_tax"]
        end
      end

      # A blank `to` is the open-ended top slab and has to stay nil rather
      # than becoming "" — the calculators read nil as "no upper bound".
      def rebuild_regimes(income_tax)
        income_tax.to_h do |regime, table|
          rows = slab_rows(table["slabs"]).reject { |from, _to, _rate| from.blank? }
          [ regime, table.except("slabs").merge(
            "slabs" => rows.map { |from, to, rate| [ from, to.presence, rate ] },
            "marginal_relief" => truthy?(table["marginal_relief"])
          ) ]
        end
      end

      # Two shapes reach here. The form posts index-keyed rows
      # (`slabs[0][from]`), which Rails hands over as a hash. A card being
      # copied — or a client posting one back unchanged — carries the stored
      # array of [from, to, rate] triples.
      def slab_rows(slabs)
        case slabs
        when Hash then slabs.values.map { |row| [ row["from"], row["to"], row["rate"] ] }
        when Array then slabs.map { |row| Array(row).first(3) }
        else []
        end
      end

      def truthy?(value) = [ true, "1", "true" ].include?(value)
    end
  end
end
