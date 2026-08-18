module HrLite
  # The one place that answers "may this person do this, and to whose rows".
  #
  # Two questions, deliberately separated:
  #
  #   can?(user, "leave.approve")            — may they at all, at any scope
  #   scope_for(user, "leave.approve")       — :self, :team, :all or nil
  #   reaches?(user, "leave.approve", other) — may they, for THIS person
  #
  # A controller that only asks the first question is the bug this class
  # exists to prevent: before roles, any admin could approve anybody's leave
  # because nothing ever asked whose leave it was.
  class Access
    # Resolution touches three tables and every screen asks several times per
    # request, so it is memoized per user for the life of the request.
    def self.for(user)
      # An unsaved user holds nothing: roles are rows keyed by user id, and
      # there is no id yet to key them by.
      return new(nil, {}) if user.nil? || user.id.nil?

      Current.access_cache ||= {}
      Current.access_cache[user.id] ||= new(user, resolve(user))
    end

    # The strongest scope held for each key across all of the user's roles.
    # Two roles granting the same key keep the WIDER of the two — roles add
    # up, they do not narrow each other.
    def self.resolve(user)
      grants = RoleGrant.joins(role: :role_assignments)
                        .where(hr_lite_role_assignments: { user_id: user.id })
                        .pluck(:permission_key, :scope)

      grants.each_with_object({}) do |(key, scope), map|
        held = map[key]
        map[key] = scope if held.nil? || Permissions.scope_covers?(scope, held)
      end
    end

    def initialize(user, permission_map)
      @user = user
      @map = permission_map
    end

    attr_reader :user

    def scope_for(key)
      @map[Permissions.validate!(key)]&.to_sym
    end

    def can?(key, scope: :self)
      held = scope_for(key)
      held.present? && Permissions.scope_covers?(held, scope)
    end

    # Whether this permission reaches a particular person's rows. `self`
    # reaches only the holder; `team` reaches their direct and indirect
    # reports; `all` reaches everyone.
    def reaches?(key, subject_user)
      return false if user.nil? || subject_user.nil?

      case scope_for(key)
      when :all then true
      when :team then subject_user.id == user.id || report_ids.include?(subject_user.id)
      when :self then subject_user.id == user.id
      else false
      end
    end

    # User ids this person's `team` scope covers, for scoping a whole
    # relation rather than checking one row at a time. `all` returns nil,
    # meaning "do not filter" — a caller that treats nil as an empty list
    # would show leadership nothing, so the callers use `scope_relation`.
    def visible_user_ids(key)
      case scope_for(key)
      when :all then nil
      when :team then [ user.id, *report_ids ]
      when :self then [ user.id ]
      else []
      end
    end

    # Narrows a relation to the rows this permission reaches. The column is
    # named because not every table calls it user_id.
    def scope_relation(relation, key, column: :user_id)
      ids = visible_user_ids(key)
      ids.nil? ? relation : relation.where(column => ids)
    end

    # Everyone below this person in the reporting chain. Walked breadth-first
    # with a seen set — EmployeeProfile validates the chain is acyclic, but a
    # cycle written directly to the database must not spin here forever.
    def report_ids
      @report_ids ||= begin
        by_manager = EmployeeProfile.where.not(manager_id: nil).pluck(:manager_id, :user_id)
                                    .group_by(&:first)
                                    .transform_values { |pairs| pairs.map(&:last) }
        found = []
        seen = [ user.id ].to_set
        queue = by_manager[user.id]&.dup || []

        while (id = queue.shift)
          next unless seen.add?(id)

          found << id
          queue.concat(by_manager[id] || [])
        end
        found
      end
    end
  end
end
