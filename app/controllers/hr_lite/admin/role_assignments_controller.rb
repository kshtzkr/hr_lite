module HrLite
  module Admin
    # Putting people into a role and taking them out again. Same gate as the
    # roles themselves: granting somebody payroll is the same act as holding
    # it, so it sits behind `role.manage`.
    class RoleAssignmentsController < LeadershipController
      skip_before_action :require_governing_access!
      before_action :require_role_management!

      def create
        role = Role.find(params[:role_id])
        user = HrLite.user_klass.find(params[:user_id])
        RoleAssignment.create!(role: role, user_id: user.id, granted_by_id: hr_current_user.id)

        redirect_to edit_admin_role_path(role),
                    notice: "#{HrLite.display_name(user)} added to #{role.name}."
      rescue ActiveRecord::RecordInvalid
        redirect_to edit_admin_role_path(params[:role_id]),
                    alert: "They already hold that role."
      end

      def destroy
        assignment = RoleAssignment.find(params[:id])
        role = assignment.role
        name = HrLite.display_name(assignment.user)

        # Locking every last person out of role management is not recoverable
        # from inside the app — it would need a console. Refuse instead.
        if last_role_manager?(assignment)
          return redirect_to edit_admin_role_path(role),
                             alert: "#{name} is the only person who can manage roles. " \
                                    "Give somebody else that permission first."
        end

        assignment.destroy!
        redirect_to edit_admin_role_path(role), notice: "#{name} removed from #{role.name}.",
                    status: :see_other
      end

      private

      def require_role_management!
        hr_require_permission!("role.manage", scope: :all)
      end

      def last_role_manager?(assignment)
        return false unless HrLite.can?(assignment.user, "role.manage", scope: :all)

        others = HrLite.users_holding("role.manage").where.not(id: assignment.user_id)
        # Another of their OWN roles may still carry it, in which case
        # removing this one changes nothing.
        others.empty? && !still_manages_without?(assignment)
      end

      def still_manages_without?(assignment)
        RoleGrant.joins(role: :role_assignments)
                 .where(hr_lite_role_assignments: { user_id: assignment.user_id })
                 .where.not(hr_lite_role_assignments: { id: assignment.id })
                 .exists?(permission_key: "role.manage", scope: "all")
      end
    end
  end
end
