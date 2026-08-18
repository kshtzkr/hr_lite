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
      end

      def update
        @declaration = find_manageable
        # Recording what the proof supported is a separate act from deciding
        # — an amount can be corrected while the decision is still pending.
        if @declaration.update(verification_params)
          redirect_to admin_tax_declaration_path(@declaration), notice: "Amounts recorded."
        else
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
