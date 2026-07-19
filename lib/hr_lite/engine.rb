module HrLite
  class Engine < ::Rails::Engine
    isolate_namespace HrLite

    config.generators do |g|
      g.test_framework :rspec
    end

    # Make the engine's plain CSS/JS visible to whichever asset pipeline the
    # host runs (Propshaft or Sprockets both read config.assets.paths).
    initializer "hr_lite.assets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.paths << root.join("app/assets/stylesheets")
        app.config.assets.paths << root.join("app/assets/javascripts")
      end
    end

    # Serve the engine's migrations straight from the gem: `bin/rails
    # db:migrate` in the host just works, and gem upgrades ship their
    # migrations automatically — nothing to copy, nothing to drift.
    #
    # Skipped when the host already copied them via
    # `hr_lite:install:migrations` (files named *.hr_lite.rb) — otherwise the
    # same tables would be created twice under different version stamps.
    initializer "hr_lite.migrations" do |app|
      next if app.root.to_s == root.to_s
      next unless HrLite::Engine.append_migrations?(app)

      config.paths["db/migrate"].expanded.each do |path|
        app.config.paths["db/migrate"] << path
      end
    end

    def self.append_migrations?(app)
      host_migrate_dirs = app.config.paths["db/migrate"].expanded
      host_migrate_dirs.none? { |dir| Dir.glob(File.join(dir, "*.hr_lite.rb")).any? }
    end
  end
end
