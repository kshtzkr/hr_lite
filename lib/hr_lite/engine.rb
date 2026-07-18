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
  end
end
