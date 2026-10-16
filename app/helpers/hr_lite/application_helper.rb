module HrLite
  module ApplicationHelper
    # Who may see a tab. OPS is the operations pages' own check; the rest are the
    # rules the old menu items had. Either way a tab never leads to a refusal.
    MANAGE = -> { hr_admin? || hr_leadership? }
    OPS = -> { hr_operations? }
    MANAGE_OR_CLAIMS = -> { hr_admin? || hr_leadership? || hr_can?("expense.approve", scope: :team) }
    LEAD = -> { hr_leadership? }
    SUPER = -> { hr_superadmin? }
    GEO = -> { HrLite.config.office_geofence }

    # The menu: nine places, each with tabs. The rail and the phone bar list
    # the places; the tab row lists the current place's tabs. A place shows
    # when one of its tabs does, and opens on the first. One URL, one home.
    SECTIONS = [
      { label: "Home", tabs: [
        { label: "Today", path: :root_path, match: [ "/" ] },
        { label: "Company overview", path: :admin_overview_path, match: [ "/admin/overview" ], if: OPS }
      ] },
      { label: "Attendance", tabs: [
        { label: "My attendance", path: :attendance_path, match: [ "/attendance", "/regularization_requests", "/wfh_requests", "/work_locations" ] },
        { label: "My work time", path: :work_time_path, match: [ "/work_time" ], if: GEO },
        { label: "Team", path: :admin_attendances_path, match: [ "/admin/attendances" ], if: OPS },
        { label: "Work modes", path: :admin_work_modes_path, match: [ "/admin/work_modes" ], if: -> { instance_exec(&GEO) && hr_operations? } },
        { label: "Team work time", path: :admin_work_time_path, match: [ "/admin/work_time" ],
          if: -> { instance_exec(&GEO) && hr_can?("work_analytics.view", scope: :team) && hr_operations? } }
      ] },
      { label: "Leave", tabs: [
        { label: "My leave", path: :leave_requests_path, match: [ "/leave_requests", "/leave_balances", "/comp_off_requests" ] },
        { label: "Calendar", path: :calendar_path, match: [ "/calendar", "/holidays" ] },
        { label: "Team balances", path: :admin_leave_balances_path, match: [ "/admin/leave_balances" ], if: OPS }
      ] },
      # Employee tier all the same — holding an approval IS the authorisation,
      # so a manager and a stand-in covering for one reach the same screen.
      # `queue:` is what the tab's page lets this viewer decide, scoped as that
      # page scopes it; the counts and the All list read it. All leads the place
      # whenever any queue tab shows.
      { label: "Inbox", tabs: [
        { label: "All", lead: true, path: :approvals_path, match: [ "/approvals" ], if: -> { HrLite::ApprovalFlow.where(active: true).exists? } },
        { label: "Leave requests", path: :admin_leave_requests_path, match: [ "/admin/leave_requests" ], if: OPS,
          queue: -> { hrl_queue(HrLite::LeaveRequest.where(status: "pending"), "leave.approve") } },
        { label: "Comp-off", path: :admin_comp_off_requests_path, match: [ "/admin/comp_off_requests" ], if: OPS,
          queue: -> { hrl_queue(HrLite::CompOffRequest.pending, "leave.approve") } },
        { label: "Attendance fixes", path: :admin_regularization_requests_path, match: [ "/admin/regularization_requests" ], if: OPS,
          queue: -> { hrl_queue(HrLite::RegularizationRequest.pending, "attendance.manage") } },
        { label: "WFH", path: :admin_wfh_requests_path, match: [ "/admin/wfh_requests" ], if: OPS,
          queue: -> { hrl_queue(HrLite::WfhRequest.pending.overlapping(Date.current, Date.current + HrLite::WfhRequest::MAX_DAYS_AHEAD), "attendance.manage") } },
        { label: "Home locations", path: :admin_work_locations_path, match: [ "/admin/work_locations" ], if: OPS,
          queue: -> { hrl_queue(HrLite::WorkLocation.pending, "attendance.manage") } },
        { label: "Claims", path: :admin_expenses_path, match: [ "/admin/expenses" ], if: -> { hr_can?("expense.approve", scope: :team) },
          queue: -> { hrl_queue(HrLite::Expense.where(status: "submitted"), "expense.approve") } },
        { label: "Documents to verify", path: :admin_documents_path, match: [ "/admin/documents" ], if: LEAD,
          queue: -> { hrl_queue(HrLite::Document.where(verification: "pending"), "document.view") } },
        { label: "CA review", path: :admin_ca_reviews_path, match: [ "/admin/ca_reviews" ],
          if: -> { hr_can?("payroll.verify", scope: :all) || hr_can?("payroll.approve", scope: :all) } }
      ] },
      { label: "Pay", tabs: [
        { label: "Slips", path: :salary_slips_path, match: [ "/salary_slips" ] },
        { label: "Expenses", path: :expenses_path, match: [ "/expenses" ], if: -> { hr_can?("expense.claim") } },
        { label: "Tax", path: :tax_declaration_path, match: [ "/tax_declaration" ] },
        { label: "Loans", path: :loans_path, match: [ "/loans" ] },
        { label: "Benefits", path: :benefits_path, match: [ "/benefits" ], if: -> { hr_can?("benefit.view") } },
        # HR approves payroll without running it; Super Admin runs it. One page.
        { label: "Payroll", path: :admin_payroll_runs_path, match: [ "/admin/payroll_runs", "/admin/salary_slips", "/admin/payroll_line_items" ],
          if: -> { hr_superadmin? || (hr_can?("payroll.approve", scope: :all) && instance_exec(&MANAGE_OR_CLAIMS)) } },
        { label: "Tax checks", path: :admin_tax_declarations_path, match: [ "/admin/tax_declarations" ],
          if: -> { hr_superadmin? || (hr_can?("tax.view", scope: :all) && instance_exec(&MANAGE_OR_CLAIMS)) } },
        { label: "Team loans", path: :admin_loans_path, match: [ "/admin/loans" ], if: SUPER },
        { label: "Team benefits", path: :admin_benefits_path, match: [ "/admin/benefits" ], if: MANAGE }
      ] },
      { label: "People", match: [ "/people" ], tabs: [
        { label: "My team", path: :team_path, match: [ "/team" ] },
        { label: "Org chart", path: :org_path, match: [ "/org" ] },
        { label: "Kudos", path: :kudos_path, match: [ "/kudos" ] },
        { label: "Employees", path: :admin_employees_path, match: [ "/admin/employees" ], if: LEAD },
        { label: "Joining & exits", path: :admin_checklists_path, match: [ "/admin/checklists" ], if: MANAGE },
        { label: "Awards", path: :admin_awards_path, match: [ "/admin/awards" ], if: LEAD },
        { label: "PIPs", path: :admin_performance_plans_path, match: [ "/admin/performance_plans" ], if: SUPER }
      ] },
      { label: "Me", tabs: [
        { label: "Profile", path: :employee_profile_path, match: [ "/profile", "/resignation" ] },
        { label: "Documents", path: :documents_path, match: [ "/documents" ] },
        { label: "ID card", path: :id_card_path, match: [ "/id_card" ] },
        { label: "Career", path: :career_path, match: [ "/career", "/appraisals" ] },
        { label: "Timeline", path: :timeline_path, match: [ "/timeline" ] }
      ] },
      { label: "Help", tabs: [
        { label: "Policies", path: :policies_path, match: [ "/policies" ], if: -> { hr_can?("policy.view", scope: :all) } },
        { label: "Ask HR", path: :hr_requests_path, match: [ "/hr_requests" ], if: -> { hr_can?("hr_request.raise") } },
        { label: "Help desk", path: :admin_hr_requests_path, match: [ "/admin/hr_requests" ], if: MANAGE },
        { label: "Manage policies", path: :admin_policies_path, match: [ "/admin/policies" ], if: -> { hr_can?("policy.manage", scope: :all) } }
      ] },
      { label: "Admin", divider: true, tabs: [
        { label: "Settings", path: :admin_leave_types_path, match: [ "/admin/leave_types", "/admin/office_locations", "/admin/holidays", "/admin/expense_categories" ], if: LEAD },
        { label: "HR settings", path: :edit_admin_setting_path, match: [ "/admin/setting" ], if: LEAD },
        { label: "Roles", path: :admin_roles_path, match: [ "/admin/roles" ], if: -> { hr_can?("role.manage", scope: :all) } },
        { label: "Statutory rates", path: :admin_statutory_rate_cards_path, match: [ "/admin/statutory_rate_cards" ], if: SUPER },
        { label: "Reports", path: :admin_reports_path, match: [ "/admin/reports" ], if: -> { hr_can?("expense.approve", scope: :all) || %w[leave.view attendance.view profile.view].any? { |key| hr_can?(key, scope: :team) } } },
        { label: "Assets", path: :admin_assets_path, match: [ "/admin/assets" ], if: MANAGE },
        { label: "Audit trail", path: :admin_audit_logs_path, match: [ "/admin/audit_logs" ], if: LEAD }
      ] }
    ].freeze

    # DayStatus kind => [code, word, month-grid cell modifier]: the code keeps a state readable without its colour.
    DAY_STATES = {
      present: [ "P", "Present", "present" ], half_day: [ "½", "Half day", "half" ],
      leave: [ "L", "Leave", "leave" ], half_day_leave: [ "½L", "Half-day leave", "half-leave" ],
      holiday: [ "H", "Holiday", "holiday" ], weekend: [ "WO", "Weekly off", "weekend" ],
      absent: [ "A", "Absent", "absent" ], upcoming: [ nil, "Upcoming", "muted" ]
    }.freeze

    # The ID card's QR: office address and phone as plain text, so any phone
    # camera shows who to call about a found card. No URL, nothing to host.
    def hrl_office_qr_svg(company, brand)
      text = [ brand, company[:address], company[:phone] ].compact_blank.join("\n")
      RQRCode::QRCode.new(text).as_svg(use_path: true, viewbox: true, color: "0F172A").html_safe
    end

    # Only items whose routes exist yet (the nav grows with each phase), and
    # whose optional `if:` holds — a link that always lands on "access
    # denied" or an empty page is worse than no link.
    def hrl_nav_items(items)
      items.select { |item| hr_lite_route?(item[:path]) && (item[:if].nil? || instance_exec(&item[:if])) }
    end

    def hr_lite_route?(helper_name)
      hr_lite.respond_to?(helper_name)
    end

    def hrl_nav_active?(item)
      item[:match].any? do |prefix|
        prefix == "/" ? request.path == hr_lite.public_send(item[:path]) : request.path.start_with?("#{hr_lite.root_path.chomp('/')}#{prefix}")
      end
    end

    # A place carries its icon (tabs carry none); `hint` adds a second line under the label.
    def hrl_nav_link(item, hint: nil)
      active = hrl_nav_active?(item)
      count = hrl_waiting(item)
      text = hint ? tag.span(safe_join([ item[:label], tag.span(hint, class: "hrl-nav__hint") ]), class: "hrl-nav__text") : item[:label]
      link_to hr_lite.public_send(item[:path]), class: "hrl-nav__link #{'hrl-nav__link--active' if active}", aria: { current: (item.fetch(:current, "page") if active) } do
        safe_join([ (hrl_icon(item[:label]) if item[:tabs]), text, (tag.span(count, class: "hrl-badge hrl-badge--warn") if count&.positive?) ].compact, " ")
      end
    end

    # How many wait in a tab's queue, or across a place's queue tabs; counted once per page.
    def hrl_waiting(item)
      queues = (item[:tabs] || [ item ]).select { |t| t[:queue] }
      queues.sum { |t| (@hrl_waiting ||= {})[t[:label]] ||= instance_exec(&t[:queue]).count } if queues.any?
    end

    # What a queue page lets this viewer decide: their reach, never their own requests.
    def hrl_queue(relation, key) = hr_access.scope_relation(relation, key).where.not(user_id: hr_current_user.id)

    # The Inbox badge's number; Home and the overview board show the same one.
    def hrl_inbox_count
      inbox = hrl_sections.find { |s| s[:label] == "Inbox" }
      inbox ? hrl_waiting(inbox).to_i : 0
    end

    # One queued request in words, and where it is decided.
    def hrl_inbox_item(tab, record)
      case record
      when HrLite::LeaveRequest
        [ "#{record.leave_type.name}, #{record.date_range_label} · #{pluralize(hrl_days(record.days_count), 'day')}", hr_lite.admin_leave_request_path(record) ]
      when HrLite::CompOffRequest then [ "Comp-off for #{record.date_worked.strftime('%a %-d %b')}", hr_lite.admin_comp_off_request_path(record) ]
      when HrLite::RegularizationRequest then [ "Attendance fix, #{record.date.strftime('%a %-d %b')}", hr_lite.admin_regularization_request_path(record) ]
      when HrLite::WfhRequest then [ "WFH, #{record.dates_label}", hr_lite.admin_wfh_request_path(record) ]
      else [ tab[:label], hr_lite.public_send(tab[:path]) ]
      end
    end

    # Everything waiting in this viewer's queues, oldest first, as [tab, record].
    def hrl_inbox_rows(limit = 50)
      inbox = hrl_sections.find { |s| s[:label] == "Inbox" } or return []
      inbox[:tabs].select { |t| t[:queue] }
                  .flat_map { |t| instance_exec(&t[:queue]).includes(:user).order(:created_at).limit(limit).map { |r| [ t, r ] } }
                  .sort_by { |_, r| r.created_at }.first(limit)
    end

    # One stroke icon per place. Decoration only: the label always shows beside it.
    ICONS = {
      "Home" => '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/>',
      "Attendance" => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
      "Leave" => '<rect x="3" y="4" width="18" height="17" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
      "Inbox" => '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.5 5.1 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.5-6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0-1.7 1.1z"/>',
      "Pay" => '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20M6 15h4"/>',
      "People" => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8"/>',
      "Me" => '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
      "Help" => '<circle cx="12" cy="12" r="9"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01"/>',
      "Admin" => '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
      "More" => '<circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/>',
      "Search" => '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>'
    }.freeze

    def hrl_icon(name)
      paths = ICONS[name] or return
      tag.svg(paths.html_safe, class: "hrl-icon", viewBox: "0 0 24 24", aria: { hidden: true }, focusable: "false") # rubocop:disable Rails/OutputSafety -- constant markup above
    end

    # Visible places, each with its visible tabs; a place links to its first
    # tab and lights for any tab's paths (plus its own, e.g. a colleague's timeline).
    def hrl_sections
      @hrl_sections ||= SECTIONS.filter_map do |section|
        rest = hrl_nav_items(section[:tabs].reject { |t| t[:lead] })
        # A lead tab also shows whenever any other tab in its place does.
        tabs = section[:tabs].select { |t| t[:lead] && hr_lite_route?(t[:path]) && (rest.any? || instance_exec(&t[:if])) } + rest
        section.merge(tabs: tabs, path: tabs.first[:path], current: "true", match: tabs.flat_map { |t| t[:match] } + section.fetch(:match, [])) if tabs.any?
      end
    end

    def hrl_current_section = hrl_sections.find { |section| hrl_nav_active?(section) }

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

    # Where an approval row actually leads. Each subject type has its own
    # decision screen; the inbox only gathers them.
    APPROVAL_PATHS = {
      "HrLite::LeaveRequest" => :admin_leave_request_path,
      "HrLite::CompOffRequest" => :admin_comp_off_request_path,
      "HrLite::RegularizationRequest" => :admin_regularization_request_path
    }.freeze

    def hrl_approval_path(approval)
      helper = APPROVAL_PATHS[approval.subject_type]
      return nil unless helper && hr_lite_route?(helper)

      hr_lite.public_send(helper, approval.subject_id)
    end

    def hrl_pagination
      render "hr_lite/shared/pagination"
    end

    # Delegates to the PORO so the host-rendered slip PDF formats identically.
    def hrl_money(amount)
      HrLite::Money.format(amount)
    end

    # Whole rupees, for salary figures that are planned rather than paid.
    def hrl_rupees(amount) = hrl_money(amount.round).delete_suffix(".00")

    # Indian-system amount in words for the slip footer. Delegates to the
    # PORO so host-rendered templates (config.render_pdf) work too.
    def hrl_amount_in_words(amount)
      HrLite::AmountInWords.words(amount)
    end

    # Day counts without a trailing ".0": 1.0 -> "1", 0.5 -> "0.5"; nil is unknown, not zero.
    def hrl_days(days) = days.nil? ? "\u2014" : number_with_precision(days, precision: 1, strip_insignificant_zeros: true)

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
      when :leave then hrl_status_badge("On leave (#{row.leave.leave_type.code})", "hrl-badge--warn", row.leave.date_range_label)
      when :half_day_leave then hrl_status_badge("Half-day leave (#{row.leave.leave_type.code})", "hrl-badge--warn", worked_hint(row))
      when :upcoming then hrl_status_badge("\u2014", "hrl-badge--muted")
      when :absent
        row.date_today? ? hrl_status_badge("Not in yet", "hrl-badge--muted") : hrl_status_badge("Absent", "hrl-badge--bad")
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

    # Lucide icons (ISC licence), one per work mode / derived status.
    MODE_ICONS = {
      "office" => '<path d="M6 22V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v18Z"/><path d="M6 12H4a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h2"/><path d="M18 9h2a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-2"/><path d="M10 6h4M10 10h4M10 14h4M10 18h4"/>',
      "wfh" => '<path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"/><path d="M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
      "travelling" => '<path d="M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z"/>',
      "outside_meeting" => '<path d="M16 20V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/><rect width="20" height="14" x="2" y="6" rx="2"/>',
      "meeting" => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
      "lunch" => '<path d="M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2M7 2v20"/><path d="M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3Zm0 0v7"/>',
      "short_break" => '<path d="M10 2v2M14 2v2M6 2v2"/><path d="M16 8a1 1 0 0 1 1 1v8a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4V9a1 1 0 0 1 1-1h14a4 4 0 1 1 0 8h-1"/>',
      "busy" => '<path d="M3 14h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a9 9 0 0 1 18 0v7a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3"/>',
      "out_of_office" => '<path d="M13 4h3a2 2 0 0 1 2 2v14M2 20h3M13 20h9M10 12v.01"/><path d="M13 4.562v16.157a1 1 0 0 1-1.242.97L5 20V5.562a2 2 0 0 1 1.515-1.94l4-1A2 2 0 0 1 13 4.561Z"/>',
      "sick_leave" => '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/><path d="M3.22 12H9.5l.5-1 2 4.5 2-7 1.5 3.5h5.27"/>',
      "holiday" => '<rect width="18" height="18" x="3" y="4" rx="2"/><path d="M16 2v4M8 2v4M3 10h18M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01M16 18h.01"/>',
      "on_leave" => '<rect width="18" height="18" x="3" y="4" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/><path d="m9 16 2 2 4-4"/>',
      "weekend" => '<rect width="18" height="18" x="3" y="4" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
      "offline" => '<circle cx="12" cy="12" r="10"/><path d="m4.9 4.9 14.2 14.2"/>',
      "custom" => '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>'
    }.freeze
    MODE_SOURCES = { "system" => "set automatically", "employee" => "set by the employee", "hr" => "set by HR" }.freeze

    # One small icon for a WorkStatus::Entry; a dot marks a system-set mode.
    # The label, source and end time live in title + screen-reader text.
    def hrl_mode_icon(entry)
      detail = [ entry.label, MODE_SOURCES[entry.source], ("until #{entry.until.strftime('%H:%M')}" if entry.until.respond_to?(:hour)) ].compact.join(" · ")
      svg = content_tag(:svg, MODE_ICONS.fetch(entry.mode, MODE_ICONS["offline"]).html_safe,
                        xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", width: 14, height: 14, fill: "none",
                        stroke: "currentColor", "stroke-width": 2, "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true)
      content_tag(:span, svg + content_tag(:span, detail, class: "hrl-sr-only"),
                  class: class_names("hrl-mode", "hrl-mode--#{entry.mode}", "hrl-mode--auto": entry.source == "system"),
                  title: detail)
    end

    # Primary + compatible overlay, e.g. office + busy.
    def hrl_status_icons(status)
      safe_join([ hrl_mode_icon(status.primary), (hrl_mode_icon(status.overlay) if status.overlay) ].compact)
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
