require "spec_helper"

ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"

# Bind engine classes (notably ApplicationController's parent) while the
# dummy initializer's configuration is in force — the per-example config
# reset below must never influence class ancestry.
Rails.application.eager_load!

# Dummy-app tables (users), then the engine's own migrations.
ActiveRecord::Migration.verbose = false
load File.expand_path("dummy/db/schema.rb", __dir__)
migration_paths = [ HrLite::Engine.root.join("db/migrate").to_s ]
ActiveRecord::MigrationContext.new(migration_paths).migrate

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

# factory_bot_rails resolves paths relative to the dummy app root; point it
# back at the gem's spec/factories instead.
FactoryBot.definition_file_paths = [ File.expand_path("factories", __dir__) ]
FactoryBot.reload

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers

  # Every example starts from the default engine configuration; examples
  # mutate HrLite.config freely and never leak into each other.
  config.before(:each) do
    HrLite.config = HrLite::Configuration.new
  end
end
