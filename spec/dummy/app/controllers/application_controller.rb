# Devise-free auth stub mirroring the contract HrLite expects from a host:
# a current_user reader and an authenticate before_action-able method.
class ApplicationController < ActionController::Base
  helper_method :current_user

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def authenticate_user!
    head :unauthorized unless current_user
  end
end
