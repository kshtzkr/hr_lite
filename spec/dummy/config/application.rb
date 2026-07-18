require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)
require "hr_lite"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.hosts.clear
    config.time_zone = "Asia/Kolkata"

    config.active_record.encryption.primary_key = "test-primary-key-000000000000000"
    config.active_record.encryption.deterministic_key = "test-deterministic-key-000000000"
    config.active_record.encryption.key_derivation_salt = "test-derivation-salt-00000000000"

    config.action_mailer.delivery_method = :test
    config.action_mailer.default_url_options = { host: "hr.example.com" }
    config.active_job.queue_adapter = :test

    config.secret_key_base = "dummy-secret-key-base-for-tests"
  end
end
