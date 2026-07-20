module HrLite
  module ApplicationHelper
    NAV_ITEMS = [
      { label: "Home",       path: :root_path,           match: [ "/" ] },
      { label: "Attendance", path: :attendance_path,     match: [ "/attendance", "/regularization_requests" ] },
      { label: "Leaves",     path: :leave_requests_path, match: [ "/leave_requests", "/leave_balances", "/comp_off_requests" ] },
      { label: "Team",       path: :team_path,           match: [ "/team" ] },
      { label: "Calendar",   path: :calendar_path,       match: [ "/calendar", "/holidays" ] },
      { label: "Org",        path: :org_path,            match: [ "/org" ] },
      { label: "Kudos",      path: :kudos_path,          match: [ "/kudos" ] },
      { label: "Slips",      path: :salary_slips_path,   match: [ "/salary_slips" ] },
      { label: "Career",     path: :career_path,         match: [ "/career", "/appraisals", "/profile" ] }
    ].freeze

    ADMIN_NAV_ITEMS = [
      { label: "Overview",        path: :admin_overview_path,        match: [ "/admin/overview" ] },
      { label: "Team attendance", path: :admin_attendances_path,     match: [ "/admin/attendances" ] },
      { label: "Approvals",       path: :admin_leave_requests_path,  match: [ "/admin/leave_requests", "/admin/leave_balances", "/admin/comp_off_requests", "/admin/regularization_requests" ] }
    ].freeze

    LEADERSHIP_NAV_ITEMS = [
      { label: "Employees", path: :admin_employees_path,        match: [ "/admin/employees" ] },
      { label: "Settings",  path: :admin_leave_types_path,      match: [ "/admin/leave_types", "/admin/office_locations", "/admin/holidays", "/admin/setting" ] },
      { label: "Audit",     path: :admin_audit_logs_path,       match: [ "/admin/audit_logs" ] }
    ].freeze

    # Money tier — only config.superadmin_emails see these.
    SUPERADMIN_NAV_ITEMS = [
      { label: "Payroll", path: :admin_payroll_runs_path, match: [ "/admin/payroll_runs", "/admin/salary_slips" ] }
    ].freeze

    # Only items whose routes exist yet (the nav grows with each phase).
    def hrl_nav_items(items)
      items.select { |item| hr_lite_route?(item[:path]) }
    end

    def hr_lite_route?(helper_name)
      hr_lite.respond_to?(helper_name)
    end

    def hrl_nav_link(item)
      href = hr_lite.public_send(item[:path])
      active = item[:match].any? do |prefix|
        prefix == "/" ? request.path == href : request.path.start_with?("#{hr_lite.root_path.chomp('/')}#{prefix}")
      end
      link_to item[:label], href, class: "hrl-nav__link #{'hrl-nav__link--active' if active}"
    end

    # Mention-marker-aware, XSS-safe kudos message rendering. Every literal
    # chunk is escaped; only markers whose id has a mention row become
    # highlighted chips (with the CURRENT display name — stale-name safe).
    def render_kudo_message(kudo)
      mentioned = kudo.kudo_mentions.index_by(&:user_id)
      out = +""
      rest = kudo.message.to_s
      while (m = HrLite::MentionParser::MARKER.match(rest))
        out << ERB::Util.html_escape(m.pre_match)
        mention = mentioned[m[2].to_i]
        if mention
          out << %(<span class="hrl-mention">@#{ERB::Util.html_escape(HrLite.display_name(mention.user))}</span>)
        else
          out << ERB::Util.html_escape("@#{m[1]}")
        end
        rest = m.post_match
      end
      out << ERB::Util.html_escape(rest)
      out.html_safe
    end

    def hrl_pagination
      render "hr_lite/shared/pagination"
    end

    def hrl_money(amount)
      return "—" if amount.nil?

      whole, fraction = HrLite::Money.round2(amount).to_s("F").split(".")
      sign = whole.start_with?("-") ? "-" : ""
      whole = whole.delete_prefix("-")
      # Indian digit grouping: last three digits together, then pairs
      # (12,34,567 — not the western 1,234,567).
      if whole.length > 3
        head = whole[0..-4].reverse.scan(/\d{1,2}/).join(",").reverse
        whole = "#{head},#{whole[-3..]}"
      end
      "#{sign}#{HrLite.config.currency_symbol}#{whole}.#{fraction.ljust(2, '0')}"
    end

    # Indian-system amount in words for the slip footer. Delegates to the
    # PORO so host-rendered templates (config.render_pdf) work too.
    def hrl_amount_in_words(amount)
      HrLite::AmountInWords.words(amount)
    end

    def hrl_duration(seconds)
      return "\u2014" if seconds.nil?

      total = seconds.to_i
      format("%dh %02dm", total / 3600, (total % 3600) / 60)
    end

    # Status badge for a TeamDay row — punch times over vague labels.
    def hrl_team_status(row)
      case row.kind
      when :holiday then hrl_status_badge("Holiday", "hrl-badge--muted", worked_hint(row))
      when :weekend then hrl_status_badge("Weekend", "hrl-badge--muted", worked_hint(row))
      when :leave then hrl_status_badge("On leave (#{row.leave.leave_type.code})", "hrl-badge--warn")
      when :half_day_leave then hrl_status_badge("Half-day leave (#{row.leave.leave_type.code})", "hrl-badge--warn", worked_hint(row))
      when :upcoming then hrl_status_badge("\u2014", "hrl-badge--muted")
      when :absent
        label = row.date_today? ? "Not in yet" : "Absent"
        hrl_status_badge(label, "hrl-badge--bad")
      else # :present / :half_day punch
        record = row.record
        if record.check_out_at
          hrl_status_badge("Done #{record.check_in_at.strftime('%H:%M')}\u2013#{record.check_out_at.strftime('%H:%M')}", "hrl-badge--ok")
        elsif row.date_today?
          hrl_status_badge("In since #{record.check_in_at.strftime('%H:%M')}", "hrl-badge--ok")
        else
          hrl_status_badge("In #{record.check_in_at.strftime('%H:%M')}, no check-out", "hrl-badge--warn")
        end
      end
    end

    # Status pill for a request lifecycle string — one colour map for every
    # list and show screen.
    def hrl_request_status_badge(status)
      css = { "approved" => "hrl-badge--ok", "rejected" => "hrl-badge--bad",
              "cancelled" => "hrl-badge--muted" }[status]
      content_tag(:span, status.humanize, class: "hrl-badge #{css}")
    end

    private

    # Always ONE root node — these land inside stacked-table flex cells,
    # where a second sibling would be flung to the far edge.
    def hrl_status_badge(label, css, hint = nil)
      badge = content_tag(:span, label, class: "hrl-badge #{css}")
      return badge unless hint

      content_tag(:span, safe_join([ badge, " ", content_tag(:span, hint, class: "hrl-small hrl-muted") ]))
    end

    # A punch on a holiday/weekend/half-day-leave is worth surfacing —
    # that's exactly what comp-off requests point at.
    def worked_hint(row)
      return nil unless row.record&.check_in_at

      "worked #{row.record.check_in_at.strftime('%H:%M')}#{row.record.check_out_at ? "\u2013#{row.record.check_out_at.strftime('%H:%M')}" : ""}"
    end
  end
end
