# Rich, deterministic sample data for the bin/demo sandbox: three tiers of
# personas and every feature pre-populated so a first-time visitor can walk
# attendance, leave, payroll, kudos and career without any setup.
module DemoSeeds
  module_function

  def run!
    leadership = User.create!(name: "Asha (Leadership)", email: "asha.lead@demo.hr", admin: true)
    admin = User.create!(name: "Rohan (Manager)", email: "rohan.admin@demo.hr")
    employee = User.create!(name: "Meera (Employee)", email: "meera@demo.hr",
                            designation: "Travel Consultant")
    colleague = User.create!(name: "Dev (Employee)", email: "dev@demo.hr",
                             designation: "Operations Executive")

    HrLite.config.public_url_base = "http://localhost:#{ENV.fetch('PORT', 3999)}/hr"
    HrLite.config.company = -> { { name: "Demo Travels Pvt Ltd", address: "42 MG Road, Bengaluru", logo_path: nil } }

    HrLite::Seeds.run! # leave types + fixed national holidays
    HrLite::RoleSeeds.call
    HrLite::StatutorySeeds.call

    # Access is roles now, not a list of addresses. Rohan is deliberately a
    # MANAGER rather than a company-wide admin: the demo is the quickest way
    # to see that a manager reaches their own reports and nobody else.
    {
      leadership => [ HrLite::Role::EMPLOYEE, HrLite::Role::LEADERSHIP, HrLite::Role::SUPER_ADMIN ],
      admin => [ HrLite::Role::EMPLOYEE, HrLite::Role::MANAGER ],
      employee => [ HrLite::Role::EMPLOYEE ],
      colleague => [ HrLite::Role::EMPLOYEE ]
    }.each do |user, role_names|
      HrLite::Role.where(name: role_names).find_each do |role|
        HrLite::RoleAssignment.create!(user_id: user.id, role: role)
      end
    end

    office = HrLite::OfficeLocation.create!(name: "Head office", lat: 12.9716, lng: 77.5946, radius_m: 300)

    [ leadership, admin, employee, colleague ].each_with_index do |user, index|
      HrLite::EmployeeProfile.create!(
        user_id: user.id, employee_code: format("EMP%03d", index + 1),
        designation: user.designation || "Manager",
        date_of_joining: Date.current.prev_year.beginning_of_year,
        department: index.even? ? "Operations" : "Sales",
        tax_regime: "new", pan_number: "ABCDE#{1234 + index}F", pf_uan: (100_000_000_000 + index).to_s,
        bank_name: "Demo Bank", bank_account_number: "0001112223#{index}", bank_ifsc: "DEMO0000001"
      )
      HrLite::SalaryStructure.create!(
        user_id: user.id, effective_from: Date.current.prev_year.beginning_of_year,
        basic: 40_000 + (index * 15_000), hra: 20_000, special_allowance: 15_000,
        pf_applicable: true, esi_applicable: true, pt_state: "karnataka"
      )
    end

    # Reporting lines: Asha (top) -> Rohan -> Meera & Dev.
    HrLite::EmployeeProfile.find_by(user_id: admin.id).update!(manager_id: leadership.id)
    HrLite::EmployeeProfile.find_by(user_id: employee.id).update!(manager_id: admin.id)
    HrLite::EmployeeProfile.find_by(user_id: colleague.id).update!(manager_id: admin.id)

    seed_attendance(employee, office)
    seed_attendance(colleague, office, flagged: true)
    seed_leaves(employee, admin)
    seed_kudos(employee, colleague, admin)
    seed_tickets(employee, colleague)
    seed_payroll(leadership)
    seed_career(employee, leadership)
    seed_services(employee, colleague, leadership)
  end

  def seed_attendance(user, office, flagged: false)
    (1..14).each do |days_ago|
      date = Date.current - days_ago
      next if date.saturday? || date.sunday?
      next if days_ago == 3 # an absence, so the month grid shows LOP red

      record = HrLite::AttendanceRecord.new(
        user_id: user.id, date: date,
        check_in_at: date.in_time_zone.change(hour: 9, min: 25 + (days_ago % 20)),
        check_out_at: date.in_time_zone.change(hour: 18, min: (days_ago * 7) % 50),
        check_in_lat: office.lat, check_in_lng: office.lng, check_in_accuracy_m: 15
      )
      record.add_flag!("Check-in 2.4 km from Head office (±35 m)") if flagged && days_ago.odd?
      record.save!
    end
  end

  def seed_leaves(employee, admin)
    casual = HrLite::LeaveType.find_by!(code: "CL")
    sick = HrLite::LeaveType.find_by!(code: "SL")

    approved = HrLite::LeaveRequest.create!(
      user_id: employee.id, leave_type: casual, reason: "Family function",
      start_date: next_working_day(Date.current + 7), end_date: next_working_day(Date.current + 7)
    )
    approved.approve!(actor: admin)

    HrLite::LeaveRequest.create!(
      user_id: employee.id, leave_type: sick, half_day: true, reason: "Dentist",
      start_date: next_working_day(Date.current + 14), end_date: next_working_day(Date.current + 14)
    )
  end

  # Pending comp-off + regularization requests so the approvals tabs and the
  # employee ticket lists have live rows on first boot.
  def seed_tickets(employee, colleague)
    HrLite::CompOffRequest.create!(
      user_id: colleague.id, date_worked: Date.current.prev_occurring(:sunday),
      reason: "Airport transfers for the weekend departures"
    )

    absent_day = (1..10).map { |n| Date.current - n }.find do |d|
      !d.saturday? && !d.sunday? &&
        !HrLite::AttendanceRecord.exists?(user_id: employee.id, date: d)
    end
    return unless absent_day

    HrLite::RegularizationRequest.create!(
      user_id: employee.id, date: absent_day,
      check_in_at: absent_day.in_time_zone.change(hour: 9, min: 40),
      check_out_at: absent_day.in_time_zone.change(hour: 18, min: 45),
      reason: "Was at the vendor meet all day — forgot both punches"
    )
  end

  def seed_kudos(employee, colleague, admin)
    kudo = HrLite::Kudo.create!(
      giver_id: admin.id, badge: "customer_hero",
      message: "Handled the stranded Bali group like a pro @[Meera](#{employee.id}) — " \
               "rebooked 12 pax overnight."
    )
    kudo.register_mentions!
    HrLite::Kudo.create!(
      giver_id: employee.id, badge: "team_player",
      message: "Thanks @[Dev](#{colleague.id}) for covering my desk during the audit."
    ).register_mentions!
  end

  # Payroll only accepts a month that has ENDED (0.5.2 — computing mid-month
  # paid for every remaining day as if it had been worked). So the published
  # run is two months back and the draft is last month; seeding a draft for
  # the CURRENT month raised on boot and took the whole demo down with it.
  def seed_payroll(leadership)
    run = HrLite::PayrollRun.create!(period_month: 2.months.ago.to_date.beginning_of_month,
                                     created_by_id: leadership.id)
    run.compute!(actor: leadership)
    run.salary_slips.find_each { |slip| slip.update!(lop_override: BigDecimal("1")) }
    HrLite::PayrollRunProcessor.call(run)
    run.finalize!(actor: leadership)
    run.publish!(actor: leadership)

    HrLite::PayrollRun.create!(period_month: Date.current.prev_month.beginning_of_month,
                               created_by_id: leadership.id) # draft for the demo to compute
  end

  def seed_career(employee, leadership)
    appraisal = HrLite::Appraisal.create!(
      user_id: employee.id, reviewer_id: leadership.id,
      period_start: Date.current.prev_year.beginning_of_year,
      period_end: Date.current.prev_year.end_of_year,
      rating: 4, outcome: "promotion", effective_date: Date.current.beginning_of_month,
      new_designation: "Senior Travel Consultant",
      strengths: "Owns escalations end to end; customers ask for her by name.",
      improvements: "Delegate vendor follow-ups instead of absorbing them."
    )
    appraisal.share!(actor: leadership)
  end

  # Expenses, benefits, a policy and an open HR request, so the new
  # self-service screens have something on them at first boot.
  def seed_services(employee, colleague, leadership)
    travel = HrLite::ExpenseCategory.create!(name: "Travel", monthly_cap: 10_000,
                                             receipt_required: false)
    HrLite::ExpenseCategory.create!(name: "Client entertainment", monthly_cap: 5_000)
    claim = HrLite::Expense.create!(user_id: employee.id, category: travel, amount: 2_450,
                                    spent_on: Date.current - 3,
                                    description: "Airport transfers for the Bali group")
    claim.submit!(actor: employee)

    health = HrLite::Benefit.create!(name: "Group health cover", kind: "health",
                                     provider: "Acme Insure", policy_number: "AC-99213",
                                     coverage: 500_000, employer_premium: 14_400,
                                     effective_from: Date.current.prev_year)
    [ employee, colleague ].each do |user|
      HrLite::BenefitEnrolment.create!(benefit: health, user_id: user.id,
                                       enrolled_on: Date.current.prev_year, dependants: 2)
    end

    HrLite::Policy.create!(title: "Code of conduct", version: 1, published: true,
                           acknowledgement_required: true,
                           effective_from: Date.current.prev_month,
                           body: "Treat colleagues and travellers with the same care.\n\n" \
                                 "Escalate early. Nobody is judged for asking.")

    HrLite::HrRequest.create!(user_id: colleague.id, category: "salary_certificate",
                              subject: "Salary certificate for a rental agreement",
                              body: "Landlord needs it before the 30th.")
  end

  def next_working_day(date)
    date += 1 while date.saturday? || date.sunday? || HrLite::Holiday.exists?(date: date)
    date
  end
end
