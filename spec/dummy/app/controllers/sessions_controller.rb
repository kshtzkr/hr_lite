class SessionsController < ApplicationController
  def create
    session[:user_id] = params[:user_id]
    head :no_content
  end

  def destroy
    session.delete(:user_id)
    head :no_content
  end
end
