require "rails_helper"
require "generators/hr_lite/install/install_generator"

RSpec.describe HrLite::Generators::InstallGenerator do
  around do |example|
    Dir.mktmpdir do |dest|
      @dest = dest
      example.run
    end
  end

  def run_generator(args = [])
    original_stdout = $stdout
    $stdout = StringIO.new
    described_class.start(args, destination_root: @dest)
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  it "writes the annotated initializer and prints next steps" do
    output = run_generator

    initializer = File.read(File.join(@dest, "config/initializers/hr_lite.rb"))
    expect(initializer).to include("HrLite.configure")
      .and include("leadership_emails")
      .and include("public_url_base")
    expect(output).to include("hr_lite:install:migrations")
      .and include("hr_lite:seed")
      .and include("db:encryption:init")
  end

  it "appends the mount line with --route" do
    FileUtils.mkdir_p(File.join(@dest, "config"))
    File.write(File.join(@dest, "config/routes.rb"),
               "Rails.application.routes.draw do\nend\n")

    run_generator([ "--route" ])

    routes = File.read(File.join(@dest, "config/routes.rb"))
    expect(routes).to include('mount HrLite::Engine => "/hr", as: :hr_lite')
  end

  it "skips the route by default" do
    FileUtils.mkdir_p(File.join(@dest, "config"))
    File.write(File.join(@dest, "config/routes.rb"),
               "Rails.application.routes.draw do\nend\n")

    run_generator

    expect(File.read(File.join(@dest, "config/routes.rb"))).not_to include("HrLite::Engine")
  end
end
