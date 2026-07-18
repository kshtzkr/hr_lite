# Must run before the engine's controllers load — the parent class is
# resolved once, at class-load time (same contract real hosts follow).
HrLite.configure do |c|
  c.parent_controller = "ApplicationController"
end
