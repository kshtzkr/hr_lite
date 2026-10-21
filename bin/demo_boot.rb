# Boots the dummy host app as a throwaway demo: fresh schema, engine
# migrations straight from the gem, rich sample data, Puma on PORT.
ENV["RAILS_ENV"] = "development"
ENV["HR_LITE_DEMO"] = "1"
port = ENV.fetch("PORT", "3999")

# Fresh database every boot (including sqlite WAL/SHM leftovers from a
# previous kill — stale ones cause disk I/O errors on the new file).
Dir[File.expand_path("../spec/dummy/db/demo.sqlite3*", __dir__)].each { |f| File.delete(f) }

require_relative "../spec/dummy/config/environment"
ActiveJob::Base.queue_adapter = :async # payroll Compute runs as a job
HrLite.config.self_regularization = { within_days: 2, per_week: 2 }
HrLite.config.work_hours = { day: 8, probation_day: 9, week: 40 }
HrLite.config.require_punch_location = true
HrLite.config.attendance_slots = true
HrLite.config.office_geofence = true
# Sample CRM for the lead picker (a real host wires its own leads).
DEMO_LEADS = { "1" => "Rahul Mehta · Bali", "2" => "Neha Rao · Ladakh", "3" => "Arjun Shah · Dubai" }.freeze
HrLite.config.crm_search = ->(_user, q) { DEMO_LEADS.select { |_, l| l.downcase.include?(q.downcase) }.map { |id, l| { id: id, label: l } } }
HrLite.config.crm_find = ->(id) { DEMO_LEADS[id.to_s] && { label: DEMO_LEADS[id.to_s], url: "#lead-#{id}" } }

# Sample hiring mailbox: logs instead of calling Google (a real host wires Gmail + Calendar).
module DemoHiring
  module_function

  def sender = { ready: true, email: "hiring@example.com", name: "Demo HR" }
  def send_email(to:, **) = Rails.logger.info("[demo hiring] email to #{to}") && { message_id: SecureRandom.hex(8), thread_id: SecureRandom.hex(8) }
  def create_event(**) = { event_id: SecureRandom.hex(8), meet_link: "https://meet.google.com/demo-link" }
  def update_event(**) = true
  def cancel_event(**) = true
  # A stand-in for the AI rewrite: swaps the greeting's name for @first_name.
  def draft_email(text:, **) = { name: "Interest check (AI)", subject: "@position at escapes.asia", body: text.sub(/\ASubject:.*\n+/, "").sub(/\AHi \w+/, "Hi @first_name") }
  def signature = "<b>Demo HR</b> | Demo Travels"
end
HrLite.config.public_url_base = "http://localhost:#{port}/hr"
HrLite.config.hiring = DemoHiring

ActiveRecord::Migration.verbose = false
load File.expand_path("../spec/dummy/db/schema.rb", __dir__)
ActiveRecord::MigrationContext.new([ HrLite::Engine.root.join("db/migrate").to_s ]).migrate

require_relative "../spec/dummy/db/demo_seeds"
DemoSeeds.run!

puts <<~BANNER

  hr_lite demo ready → http://localhost:#{port}

  Personas (one click to sign in):
    • Asha (Leadership) — payroll, policies, employees, audit trail
    • Rohan (Admin)     — approvals, team attendance, overview board
    • Meera / Dev       — punch, leaves, slips, kudos, career

  Data resets on every restart. Ctrl-C to stop.

BANNER

require "puma"
require "puma/configuration"
require "puma/launcher"

configuration = Puma::Configuration.new do |config|
  config.app Rails.application
  config.port port.to_i
  config.environment "development"
  config.workers 0
  config.threads 1, 4
end

Puma::Launcher.new(configuration).run
