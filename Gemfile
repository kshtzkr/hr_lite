source "https://rubygems.org"

# Specify your gem's dependencies in hr_lite.gemspec.
gemspec

gem "puma"

gem "sqlite3"

# Dummy-app asset serving (a real host brings its own pipeline).
gem "propshaft"

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

group :development, :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "simplecov", require: false
end
