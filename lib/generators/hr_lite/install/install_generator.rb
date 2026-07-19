require "rails/generators"
require "rails/generators/base"

module HrLite
  module Generators
    # `rails g hr_lite:install` — drops the annotated initializer and prints
    # the remaining wiring steps. With --route it also appends a mount line.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :route, type: :boolean, default: false,
                           desc: "Append `mount HrLite::Engine => \"/hr\"` to config/routes.rb"

      def copy_initializer
        template "initializer.rb", "config/initializers/hr_lite.rb"
      end

      def add_route
        return unless options[:route]

        route 'mount HrLite::Engine => "/hr", as: :hr_lite'
      end

      def show_next_steps
        readme "AFTER_INSTALL" if behavior == :invoke
      end
    end
  end
end
