if ENV["COVERAGE"] == "1" || ENV["CI"]
  require "simplecov"
  SimpleCov.start "rails" do
    enable_coverage :branch
    add_filter %r{^/spec/}
    add_filter "lib/hr_lite/version.rb" # loaded by bundler before SimpleCov starts
    # The gem's own code only — the dummy app is a fixture, not shipped code.
    root File.expand_path("..", __dir__)
    track_files "{app,lib}/**/*.rb"
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
