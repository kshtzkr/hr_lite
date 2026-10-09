module HrLite
  # The employee's own declaration for a financial year. Replaces an admin
  # typing one lump sum into the profile: the whole year's TDS is projected
  # from this, so the person whose money it is fills it in.
  class TaxDeclarationsController < ApplicationController
    def show
      @declaration = current_declaration || build_declaration
      # A saved draft holds only its claims; the rest still need a line to fill.
      fill_missing_sections(@declaration)
      @regime = @declaration.regime
      @tax = TaxComputation.new(user: hr_current_user, declaration: @declaration)
    end

    # The form posts here as it is typed in: the tax worked out on what is on
    # screen, nothing saved.
    def preview
      declaration = current_declaration || TaxDeclaration.new(user_id: hr_current_user.id, financial_year: financial_year)
      declaration.regime = declaration_params[:regime] if declaration_params[:regime]
      declaration.tax_declaration_items_attributes = preview_items
      render partial: "hr_lite/tax/computation", locals: { tax: TaxComputation.new(user: hr_current_user, declaration: declaration), both: false }
    end

    def update
      # A bare record, not the form's scaffold: `build_declaration` fills in
      # one blank line per section so the form is a list rather than an empty
      # box, and saving those blanks fails a NOT NULL amount.
      @declaration = current_declaration ||
                     TaxDeclaration.new(user_id: hr_current_user.id,
                                        financial_year: financial_year, regime: employee_regime)
      # A verified declaration is what payroll is deducting against; changing
      # it would silently re-open a decision HR has already made.
      if @declaration.verified?
        return redirect_to tax_declaration_path,
                           alert: "This year's declaration is verified. Ask HR to reopen it."
      end

      if @declaration.update(declaration_params)
        return submit if params[:submit_to_hr] # Submit to HR saves what is on screen first

        redirect_to tax_declaration_path, notice: "Saved."
      else
        # Re-render needs the full set of lines back, or the form loses the
        # sections the person had not filled in yet.
        fill_missing_sections(@declaration)
        @tax = TaxComputation.new(user: hr_current_user, declaration: @declaration)
        render :show, status: :unprocessable_entity
      end
    end

    def submit
      @declaration = current_declaration
      return redirect_to tax_declaration_path, alert: "Nothing to submit yet." if @declaration.nil?

      @declaration.submit!(actor: hr_current_user)
      redirect_to tax_declaration_path, notice: "Submitted — HR will check the proof."
    rescue ActiveRecord::RecordInvalid
      redirect_to tax_declaration_path, alert: "Only a draft can be submitted."
    end

    private

    def financial_year
      FinancialYear.start_for(params[:financial_year].present? ? Date.parse(params[:financial_year]) : Date.current)
    rescue Date::Error
      FinancialYear.start_for(Date.current)
    end

    def current_declaration
      TaxDeclaration.find_by(user_id: hr_current_user.id, financial_year: financial_year)
    end

    def build_declaration
      declaration = TaxDeclaration.new(user_id: hr_current_user.id, financial_year: financial_year,
                                       regime: employee_regime)
      # One blank line per section, so the form is a list of the things a
      # person can actually claim rather than an empty box and a plus button.
      fill_missing_sections(declaration)
      declaration
    end

    # Every section gets a line, whether or not it has been claimed yet.
    def fill_missing_sections(declaration)
      present = declaration.tax_declaration_items.map(&:section)
      (TaxDeclarationItem::SECTIONS - present).each do |section|
        declaration.tax_declaration_items.build(section: section)
      end
    end

    # Lines for a preview: amounts only, never files (a blanked line is marked
    # for removal, which the computation skips). Already filtered by the
    # permit in declaration_params, so plain hashes are safe here.
    def preview_items
      (declaration_params[:tax_declaration_items_attributes] || {}).to_unsafe_h.transform_values { |row| row.except("proofs") }
    end

    def employee_regime
      EmployeeProfile.find_by(user_id: hr_current_user.id)&.tax_regime.presence || "new"
    end

    # The form posts a line for every section, because that is what a list of
    # claimable things looks like. Most of them are blank — a section with no
    # amount is not a claim, and saving it violates a NOT NULL amount.
    # An EXISTING line blanked out is a claim being withdrawn, so it is
    # destroyed rather than skipped.
    def declaration_params
      permitted = params.require(:tax_declaration).permit(
        :regime,
        tax_declaration_items_attributes: [ :id, :section, :label, :declared_amount, :senior, :landlord_pan, :_destroy, { proofs: [] } ]
      )
      items = permitted[:tax_declaration_items_attributes]
      return permitted if items.blank?

      permitted[:tax_declaration_items_attributes] = items.to_h.filter_map { |key, row|
        next [ key, row.merge("_destroy" => "1") ] if row["declared_amount"].blank? && row["id"].present?
        next if row["declared_amount"].blank?

        [ key, row ]
      }.to_h
      permitted
    end
  end
end
