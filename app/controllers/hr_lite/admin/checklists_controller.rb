module HrLite
  module Admin
    # Joining and leaving, step by step, with what is overdue at the top.
    class ChecklistsController < BaseController
      skip_before_action :require_operations_access!
      before_action :require_checklists!

      def index
        @kind = params[:kind].presence_in(ChecklistTemplate::KINDS) || "onboarding"
        @items = ChecklistItem.for_kind(@kind).outstanding.includes(:user)
                              .order(Arel.sql("due_on IS NULL, due_on"))
        @overdue = @items.select(&:overdue?)
      end

      def complete
        item = ChecklistItem.find(params[:id])
        item.complete!(actor: hr_current_user, note: params[:note])
        redirect_to admin_checklists_path(kind: item.kind), notice: "#{item.title} — done."
      end

      def reopen
        item = ChecklistItem.find(params[:id])
        item.reopen!(actor: hr_current_user)
        redirect_to admin_checklists_path(kind: item.kind), notice: "#{item.title} — reopened."
      end

      private

      def require_checklists! = hr_require_permission!("checklist.manage", scope: :all)
    end
  end
end
