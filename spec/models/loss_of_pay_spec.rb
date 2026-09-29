require "rails_helper"

# Leave uses the balance first; the days beyond it are loss of pay, cut at
# the month's gross / calendar days. July 2027: 31 days, sat_sun weekends,
# 22 working days.
RSpec.describe "Leave beyond the balance is loss of pay" do
  let(:user) { create(:user, name: "Asha") }
  let(:admin) { create(:user, :admin) }
  let(:type) { create(:leave_type, name: "Casual", annual_quota: 0) }
  let(:year) { HrLite::LeaveYear.key_for(Date.new(2027, 7, 12)) }

  before { travel_to(Date.new(2027, 7, 1)) }
  after { travel_back }

  def credit(days) = HrLite::LeaveBalance.adjust!(user, type, year, delta: days, note: "opening")

  def approve(from, to, **attrs)
    request = create(:leave_request, { user: user, leave_type: type, start_date: from, end_date: to }.merge(attrs))
    request.approve!(actor: admin)
    request.reload
  end

  it "covers the earliest days and leaves the rest unpaid, without overdrawing the balance" do
    credit(1.5)
    request = approve(Date.new(2027, 7, 12), Date.new(2027, 7, 14))

    expect(request.paid_days).to eq(1.5)
    expect((12..14).map { |d| request.unpaid_on(Date.new(2027, 7, d)) }).to eq([ 0, 0.5, 1 ])
    expect(request.balance.available(as_of: Date.new(2027, 7, 14))).to eq(0)
  end

  it "leaves a request the balance fully covers untouched" do
    credit(3)
    request = approve(Date.new(2027, 7, 12), Date.new(2027, 7, 14))

    expect(request.paid_days).to be_nil
    expect(request.unpaid_on(Date.new(2027, 7, 14))).to eq(0)
  end

  it "covers only whole half-days of a fractional balance" do
    credit(1.2)
    expect(approve(Date.new(2027, 7, 12), Date.new(2027, 7, 13)).paid_days).to eq(1)
  end

  it "makes an unpaid half-day of a half-day with no balance" do
    request = approve(Date.new(2027, 7, 12), Date.new(2027, 7, 12), half_day: true)
    expect(request.paid_days).to eq(0)
    expect(request.unpaid_on(Date.new(2027, 7, 12))).to eq(0.5)
  end

  it "cuts the unpaid days from that month's pay at gross / days in month" do
    credit(1.5)
    approve(Date.new(2027, 7, 12), Date.new(2027, 7, 14))
    working = (Date.new(2027, 7, 1)..Date.new(2027, 7, 31)).reject { |d| d.saturday? || d.sunday? || (12..14).cover?(d.day) }
    working.each { |d| create(:attendance_record, :checked_in, user: user, date: d) }
    profile = create(:employee_profile, user: user, date_of_joining: Date.new(2026, 1, 1))
    structure = create(:salary_structure, user: user, basic: 31000, hra: nil, special_allowance: nil)

    travel_to(Date.new(2027, 8, 2))
    attrs = HrLite::SlipBuilder.call(run: create(:payroll_run, period_month: Date.new(2027, 7, 1)),
                                     user: user, structure: structure, profile: profile)
    expect(attrs[:lop_days]).to eq(1.5)
    expect(attrs[:gross_earnings]).to eq(29_500)
  end

  it "charges each unpaid day of a leave spanning two months to its own month" do
    credit(1)
    request = approve(Date.new(2027, 7, 30), Date.new(2027, 8, 2)) # Fri, then Mon (weekend between is paid)

    travel_to(Date.new(2027, 8, 31))
    expect(HrLite::AttendanceSummary.for(user: user, month: Date.new(2027, 7, 1))[:unpaid_leave]).to eq(0)
    expect(HrLite::AttendanceSummary.for(user: user, month: Date.new(2027, 8, 1))[:unpaid_leave]).to eq(1)
    expect(request.paid_days).to eq(1)
  end

  it "warns the employee on applying that days past the balance will be unpaid", type: :request do
    credit(1)
    sign_in user
    post "/hr/leave_requests", params: { leave_request: { leave_type_id: type.id, start_date: "2027-07-12", end_date: "2027-07-14" } }
    expect(flash[:notice]).to include("2.0 day(s) are beyond your balance")
  end
end
