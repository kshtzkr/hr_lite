module HrLite
  # Request-scoped actor for audit logging. Set by ApplicationController,
  # readable from any model callback without threading it through.
  class Current < ActiveSupport::CurrentAttributes
    attribute :actor
  end
end
