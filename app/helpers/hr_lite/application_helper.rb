module HrLite
  module ApplicationHelper
    NAV_ITEMS = [
      { label: "Home",       path: :root_path,           match: [ "/" ] },
      { label: "Attendance", path: :attendance_path,     match: [ "/attendance" ] },
      { label: "Leaves",     path: :leave_requests_path, match: [ "/leave_requests", "/leave_balances" ] },
      { label: "Calendar",   path: :calendar_path,       match: [ "/calendar", "/holidays" ] },
      { label: "Kudos",      path: :kudos_path,          match: [ "/kudos" ] },
      { label: "Slips",      path: :salary_slips_path,   match: [ "/salary_slips" ] },
      { label: "Career",     path: :career_path,         match: [ "/career", "/appraisals", "/profile" ] }
    ].freeze

    ADMIN_NAV_ITEMS = [
      { label: "Overview",        path: :admin_overview_path,        match: [ "/admin/overview" ] },
      { label: "Team attendance", path: :admin_attendances_path,     match: [ "/admin/attendances" ] },
      { label: "Approvals",       path: :admin_leave_requests_path,  match: [ "/admin/leave_requests", "/admin/leave_balances" ] }
    ].freeze

    LEADERSHIP_NAV_ITEMS = [
      { label: "Employees", path: :admin_employees_path,        match: [ "/admin/employees" ] },
      { label: "Payroll",   path: :admin_payroll_runs_path,     match: [ "/admin/payroll_runs", "/admin/salary_slips" ] },
      { label: "Settings",  path: :admin_leave_types_path,      match: [ "/admin/leave_types", "/admin/office_locations", "/admin/holidays", "/admin/setting" ] },
      { label: "Audit",     path: :admin_audit_logs_path,       match: [ "/admin/audit_logs" ] }
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
  end
end
