# Minimal stand-in for a host app's user model. The engine only relies on
# the configured hooks (display name, admin_check, leadership emails), never
# on this class directly.
class User < ActiveRecord::Base
  def display_name
    name.presence || email
  end

  def admin?
    admin
  end
end
