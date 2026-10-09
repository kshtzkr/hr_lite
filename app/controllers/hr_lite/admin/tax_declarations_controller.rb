module HrLite
  module Admin
    # HR checking the proof behind a declaration, line by line. The verified
    # amount is what payroll deducts against once this is done, so it is
    # entered per section rather than accepted wholesale.
    class TaxDeclarationsController < BaseController
      skip_before_action :require_operations_access!
      before_action :require_tax_access!

      def index
        @status = params[:status].presence_in(TaxDeclaration::STATUSES) || "submitted"
        @declarations = paginate(
          hr_scope(TaxDeclaration.includes(:user, :tax_declaration_items), "tax.view")
            .where(status: @status).order(created_at: :desc)
        )
      end

      def show
        @declaration = find_visible
        @tax = TaxComputation.new(user: @declaration.user, declaration: @declaration)
      end

      # Everyone's tax this year, worked out now, whether or not they declared.
      def overview
        visible = hr_access.visible_user_ids("tax.view")
        profiles = EmployeeProfile.active_for(Date.current).includes(:user).order(:employee_code)
        profiles = profiles.where(user_id: visible) if visible
        @profiles = paginate(profiles)
        @declarations = TaxDeclaration.where(user_id: @profiles.map(&:user_id),
                                             financial_year: FinancialYear.start_for(Date.current)).index_by(&:user_id)
      end

      # Anyone's full working, filed or not.
      def person
        @person = HrLite.user_klass.find(params[:user_id])
        hr_require_reach!("tax.view", @person)
        @tax = TaxComputation.new(user: @person)
      end

      # The proof, through a permission check and an audit row — never a bare blob link.
      def proof
        declaration = find_visible
        file = declaration.tax_declaration_items.flat_map { |item| item.proofs.to_a }.find { |p| p.id == params[:proof_id].to_i }
        raise ActiveRecord::RecordNotFound unless file

        AuditLog.record!(action: "tax_proof.downloaded", subject: declaration, actor: hr_current_user,
                         changes: { "file" => file.filename.to_s, "owner" => HrLite.display_name(declaration.user) })
        redirect_to Rails.application.routes.url_helpers.rails_blob_path(file, disposition: "attachment", only_path: true),
                    allow_other_host: false
      end

      # One click when the proof matches the claim: every unchecked line is
      # accepted at what was claimed (the legal limit still applies), then verified.
      def accept_all
        declaration = find_manageable
        TaxDeclaration.transaction do
          declaration.tax_declaration_items.each do |item|
            item.update!(verified_amount: item.declared_amount) if item.verified_amount.nil?
          end
          declaration.verify!(actor: hr_current_user, note: "Proof accepted")
        end
        redirect_to admin_tax_declarations_path, notice: "Accepted and verified — payroll uses these amounts now."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_tax_declaration_path(declaration), alert: "Only a submitted declaration can be accepted."
      end

      def update
        @declaration = find_manageable
        # Recording what the proof supported is a separate act from deciding
        # — an amount can be corrected while the decision is still pending.
        if @declaration.update(verification_params)
          redirect_to admin_tax_declaration_path(@declaration), notice: "Amounts recorded."
        else
          @tax = TaxComputation.new(user: @declaration.user, declaration: @declaration)
          render :show, status: :unprocessable_entity
        end
      end

      def verify
        declaration = find_manageable
        declaration.verify!(actor: hr_current_user, note: params[:note])
        redirect_to admin_tax_declarations_path, notice: "Verified — payroll will use the checked amounts."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_tax_declaration_path(declaration), alert: "Only a submitted declaration can be verified."
      end

      def reject
        declaration = find_manageable
        declaration.reject!(actor: hr_current_user, note: params[:note].to_s.strip)
        redirect_to admin_tax_declarations_path, notice: "Sent back to the employee."
      rescue ArgumentError
        redirect_to admin_tax_declaration_path(declaration),
                    alert: "Say what is missing — they have to know what to fix."
      end

      private

      def require_tax_access!
        hr_require_permission!("tax.view", scope: :all)
      end

      def find_visible
        declaration = TaxDeclaration.includes(:tax_declaration_items).find(params[:id])
        hr_require_reach!("tax.view", declaration.user)
        declaration
      end

      def find_manageable
        declaration = TaxDeclaration.find(params[:id])
        hr_require_reach!("tax.manage", declaration.user)
        raise ActiveRecord::RecordNotFound if declaration.user_id == hr_current_user.id # never one's own
        declaration
      end

      def verification_params
        params.require(:tax_declaration).permit(
          tax_declaration_items_attributes: %i[id verified_amount]
        )
      end
    end
  end
end
