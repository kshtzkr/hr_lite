# Devise-free auth stub mirroring the contract HrLite expects from a host:
# a current_user reader and an authenticate before_action-able method.
class ApplicationController < ActionController::Base
  helper_method :current_user

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def authenticate_user!
    return if current_user

    # Humans in the bin/demo sandbox land on the persona picker; specs keep
    # the bare 401 contract.
    if ENV["HR_LITE_DEMO"] == "1"
      redirect_to "/"
    else
      head :unauthorized
    end
  end
end
