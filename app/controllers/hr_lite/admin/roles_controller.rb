module HrLite
  module Admin
    # Who may do what. Gated on `role.manage`, which by default only the
    # money tier holds — the authority to grant yourself payroll is the
    # authority to read everyone's pay, so it lives with the pay.
    class RolesController < LeadershipController
      skip_before_action :require_governing_access!
      before_action :require_role_management!

      def index
        @roles = Role.alphabetical.includes(:role_grants, :role_assignments)
      end

      def new
        @role = Role.new
      end

      def create
        @role = Role.new(role_params)
        if @role.save
          @role.replace_grants!(grant_params)
          redirect_to admin_roles_path, notice: "#{@role.name} created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @role = Role.find(params[:id])
      end

      def update
        @role = Role.find(params[:id])
        if @role.update(role_params)
          @role.replace_grants!(grant_params)
          redirect_to admin_roles_path, notice: "#{@role.name} updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        role = Role.find(params[:id])
        if role.destroy
          redirect_to admin_roles_path, notice: "#{role.name} deleted.", status: :see_other
        else
          redirect_to admin_roles_path, alert: role.errors.full_messages.to_sentence,
                      status: :see_other
        end
      end

      private

      def require_role_management!
        hr_require_permission!("role.manage", scope: :all)
      end

      def role_params
        permitted = params.require(:role).permit(:name, :description)
        # A built-in role's NAME is what the seed, the upgrade migration and
        # the specs all identify it by; the model refuses a rename, and not
        # sending one keeps the form from failing on an untouched field.
        @role&.system? ? permitted.except(:name) : permitted
      end

      # The form posts the COMPLETE picture, so a permission absent from it is
      # one being taken away. "none" is how the form says "not granted".
      def grant_params
        params.fetch(:grants, {}).permit(Permissions::KEYS).to_h
      end
    end
  end
end
