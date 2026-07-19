# Boots the dummy host app as a throwaway demo: fresh schema, engine
# migrations straight from the gem, rich sample data, Puma on PORT.
ENV["RAILS_ENV"] = "development"
ENV["HR_LITE_DEMO"] = "1"
port = ENV.fetch("PORT", "3999")

# Fresh database every boot (including sqlite WAL/SHM leftovers from a
# previous kill — stale ones cause disk I/O errors on the new file).
Dir[File.expand_path("../spec/dummy/db/demo.sqlite3*", __dir__)].each { |f| File.delete(f) }

require_relative "../spec/dummy/config/environment"

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
