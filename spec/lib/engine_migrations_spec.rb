require "rails_helper"

RSpec.describe "Engine-served migrations" do
  it "appends the gem's db/migrate to the host's migration paths" do
    expect(Rails.application.config.paths["db/migrate"].expanded)
      .to include(HrLite::Engine.root.join("db/migrate").to_s)
  end

  describe ".append_migrations?" do
    it "is true for a host without copied hr_lite migrations" do
      Dir.mktmpdir do |dir|
        app = instance_double(Rails::Application)
        paths = instance_double(Rails::Paths::Path, expanded: [ dir ])
        config = instance_double(Rails::Application::Configuration, paths: { "db/migrate" => paths })
        allow(app).to receive(:config).and_return(config)

        expect(HrLite::Engine.append_migrations?(app)).to be(true)
      end
    end

    it "steps aside when the host copied migrations via install:migrations" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "20990101000000_create_hr_lite_kudos.hr_lite.rb"), "# copy")
        app = instance_double(Rails::Application)
        paths = instance_double(Rails::Paths::Path, expanded: [ dir ])
        config = instance_double(Rails::Application::Configuration, paths: { "db/migrate" => paths })
        allow(app).to receive(:config).and_return(config)

        expect(HrLite::Engine.append_migrations?(app)).to be(false)
      end
    end
  end
end
