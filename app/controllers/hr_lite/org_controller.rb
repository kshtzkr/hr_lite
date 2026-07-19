module HrLite
  # The everyone-visible org chart: who reports to whom, plus the viewer's
  # own reporting line labelled L1/L2/... Only names, designations and
  # departments — never salary, identity numbers or any other private data.
  class OrgController < ApplicationController
    def show
      profiles = EmployeeProfile.includes(:user)
                                .where("date_of_exit IS NULL OR date_of_exit >= ?", Date.current)
                                .to_a
      @by_user = profiles.index_by(&:user_id)
      @children = profiles.group_by(&:manager_id)
      # Roots: no manager, or the manager has no active profile (their own
      # subtree still renders under them via @children).
      @roots = profiles.select { |p| p.manager_id.nil? || !@by_user.key?(p.manager_id) }
                       .sort_by { |p| HrLite.display_name(p.user).downcase }
      @own_profile = @by_user[hr_current_user.id]
      exited = EmployeeProfile.where(date_of_exit: ...Date.current).pluck(:user_id).to_set
      @own_chain = (@own_profile&.reporting_chain || []).reject { |boss| exited.include?(boss.id) }
    end
  end
end
