require "rails_helper"

RSpec.describe HrLite::AttendanceCloseJob do
  let(:tuesday) { Date.new(2027, 7, 6) }
  let(:bells) { [] }

  before do
    HrLite.config.notify = ->(**kw) { bells << kw }
    travel_to(ist(2027, 7, 7, 6)) # the morning after Tuesday
  end

  after { travel_back }

  def ist(*args) = Time.find_zone("Asia/Kolkata").local(*args)

  def open_punch(**attrs)
    create(:attendance_record, date: tuesday, check_in_at: tuesday.in_time_zone.change(hour: 10), **attrs)
  end

  it "checks out an open punch as a half day, tells who forgot, and leaves a closed day alone" do
    open = open_punch
    done = create(:attendance_record, :checked_out, date: tuesday)
    absent = create(:user)

    expect { described_class.perform_now }.to have_enqueued_mail(HrLite::EventMailer, :event).twice

    open.reload
    expect(open.check_out_at).to be_within(1.second).of(tuesday.end_of_day)
    expect(open.status).to eq("half_day")
    expect(open.regularization_note).to eq(HrLite::AttendanceRecord::AUTO_CHECKOUT_NOTE)
    expect(open).not_to be_regularized
    expect(done.reload.status).to eq("present")
    expect(bells.map { |b| [ b[:user], b[:kind], b[:title] ] }).to contain_exactly(
      [ open.user, "attendance.missed_check_out", "You didn't check out on 06 Jul — marked half day" ],
      [ absent, "attendance.missed_check_in", "You didn't check in on 06 Jul — marked absent" ]
    )
    expect(bells.first).to include(body: "Raise a regularization ticket to get it fixed.",
                                   path: "/regularization_requests/new?date=2027-07-06")
    # The next morning's board still counts the day it closed.
    expect(HrLite::OverviewQuery.new(date: tuesday + 1).kpis[:missing_checkout]).to eq(1)
  end

  it "closes today when it runs at 23:55" do
    open = open_punch
    travel_to(ist(2027, 7, 6, 23, 55))
    described_class.perform_now
    expect(open.reload.status).to eq("half_day")
  end

  it "closes yesterday when a retry runs after midnight" do
    user = create(:user)
    travel_to(ist(2027, 7, 6, 20))
    HrLite::AttendancePuncher.call(user: user, kind: :check_in, lat: 12.9, lng: 77.6)
    travel_to(ist(2027, 7, 7, 0, 30))
    expect(HrLite::AttendancePuncher.call(user: user, kind: :check_out, lat: 12.9, lng: 77.6)).to be_ok
    travel_to(ist(2027, 7, 7, 6, 7)) # a retry, minutes after the schedule

    described_class.perform_now
    record = HrLite::AttendanceRecord.find_by!(user: user, date: tuesday)
    expect([ record.status, record.check_out_at ]).to eq([ "present", ist(2027, 7, 7, 0, 30) ])
    expect(bells).to be_empty
  end

  it "points at self-fix when the host allows it" do
    HrLite.config.self_regularization = { within_days: 2, per_week: 2 }
    create(:user)
    described_class.perform_now
    expect(bells.sole[:body]).to eq("Fix it yourself by 08 Jul (up to 2 a week), or raise a ticket for HR.")
  end

  it "skips weekends and holidays" do
    open = open_punch
    described_class.perform_now(date: Date.new(2027, 7, 10))
    create(:holiday, date: tuesday)
    described_class.perform_now
    expect(bells).to be_empty
    expect(open.reload.check_out_at).to be_nil
  end

  it "leaves a day on approved leave, half day included, as it is" do
    open = open_punch
    create(:leave_request, :approved, user: open.user, start_date: tuesday, end_date: tuesday, half_day: true)
    create(:leave_request, :approved, start_date: tuesday, end_date: tuesday)
    bells.clear
    described_class.perform_now
    expect(bells).to be_empty
    expect(open.reload.check_out_at).to be_nil
  end

  it "validates config.self_regularization at assignment" do
    HrLite.config.self_regularization = nil
    expect { HrLite.config.self_regularization = { within_days: 0, per_week: 2 } }.to raise_error(ArgumentError)
    expect { HrLite.config.self_regularization = { within_days: 2 } }.to raise_error(ArgumentError)
    expect { HrLite.config.self_regularization = "2" }.to raise_error(ArgumentError)
  end
end
