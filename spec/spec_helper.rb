if ENV["COVERAGE"] == "1" || ENV["CI"]
  require "simplecov"
  SimpleCov.start "rails" do
    enable_coverage :branch
    add_filter %r{^/spec/}
    add_filter "lib/hr_lite/version.rb" # loaded by bundler before SimpleCov starts
    add_filter %r{/generators/.*/templates/} # generator templates are copied, not executed
    # The gem's own code only — the dummy app is a fixture, not shipped code.
    root File.expand_path("..", __dir__)
    track_files "{app,lib}/**/*.rb"

    # The README claimed 100% line coverage and nothing enforced it, so the
    # number was whatever the last local run happened to produce. These
    # thresholds FAIL the build — a payroll engine is the wrong place to
    # find out afterwards that a branch was never executed.
    #
    # LINE coverage is the ratchet: 100%, per file 90%, and it has caught
    # real defects — an unreachable `cancel_all!`, three untested money
    # guards, a pluralisation branch that could not fire.
    #
    # BRANCH coverage is a floor, not a ratchet, and deliberately so. Its
    # denominator grows with every subsystem added, so ratcheting it charges
    # each feature PR a tax for branches in files it never touched — which
    # buys contrived specs, not confidence. It moved 88 -> 90.8 while the
    # codebase was stable, then down to 90 when the approval engine and the
    # payroll heads added ~150 branches in two releases.
    #
    # If it falls below 90, that is worth reading as a signal rather than
    # adjusting again.
    minimum_coverage line: 100, branch: 90
    # One thin file dragging the average up must not hide another at 40%.
    coverage(:line) { minimum_per_file 90 }
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
