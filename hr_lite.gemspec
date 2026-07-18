require_relative "lib/hr_lite/version"

Gem::Specification.new do |spec|
  spec.name        = "hr_lite"
  spec.version     = HrLite::VERSION
  spec.authors     = [ "kshitiz sinha" ]
  spec.email       = [ "kshtzkr@gmail.com" ]
  spec.homepage    = "https://github.com/kshtzkr/hr_lite"
  spec.summary     = "Lightweight Keka-style HRMS engine for Rails."
  spec.description = "Mountable Rails engine providing attendance with geolocation, " \
                     "leave management, holiday calendar, Indian payroll (PF/ESI/PT/TDS) " \
                     "with salary-slip PDFs, kudos with @mentions, appraisals and " \
                     "promotions — integrated into a host app via config hooks."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "CHANGELOG.md"]
  end

  spec.required_ruby_version = ">= 3.2"

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "csv" # payout register export; no longer a default gem since Ruby 3.4
end
