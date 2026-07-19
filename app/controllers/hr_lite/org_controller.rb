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
      build_tree(profiles)
      @own_profile = @by_user[hr_current_user.id]
      exited = EmployeeProfile.where(date_of_exit: ...Date.current).pluck(:user_id).to_set
      @own_chain = (@own_profile&.reporting_chain || []).reject { |boss| exited.include?(boss.id) }
    end

    private

    # BFS from the natural roots, then promote anything unreached (a
    # manager cycle that slipped past validation must degrade to extra
    # roots, not silently vanish). @tree_children only ever contains
    # forward edges, so the recursive partial always terminates and every
    # active profile renders exactly once.
    def build_tree(profiles)
      children = profiles.group_by(&:manager_id)
      @roots = profiles.select { |p| p.manager_id.nil? || !@by_user.key?(p.manager_id) }
                       .sort_by { |p| HrLite.display_name(p.user).downcase }
      @tree_children = Hash.new { |hash, key| hash[key] = [] }
      visited = {}
      walk = lambda do |node|
        (children[node.user_id] || []).each do |child|
          next if visited[child.user_id]

          visited[child.user_id] = true
          @tree_children[node.user_id] << child
          walk.call(child)
        end
      end
      @roots.each { |root| visited[root.user_id] = true }
      @roots.each { |root| walk.call(root) }

      profiles.sort_by(&:id).each do |profile|
        next if visited[profile.user_id]

        visited[profile.user_id] = true
        @roots << profile
        walk.call(profile)
      end
    end
  end
end
