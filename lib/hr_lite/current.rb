module HrLite
  # Request-scoped actor for audit logging. Set by ApplicationController,
  # readable from any model callback without threading it through.
  class Current < ActiveSupport::CurrentAttributes
    attribute :actor
    # Resolved permissions, keyed by user id. Every screen asks several times
    # per request and resolution joins three tables; CurrentAttributes is
    # reset between requests, so a role change takes effect on the next one.
    attribute :access_cache
  end
end
