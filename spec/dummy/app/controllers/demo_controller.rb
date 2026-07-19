# Persona picker for the bin/demo sandbox: one click signs you in as an
# employee / admin / leadership user so anyone can walk every tier without
# a real auth stack. Active only under bin/demo (HR_LITE_DEMO=1).
class DemoController < ApplicationController
  before_action :demo_only!

  def index
    @personas = User.order(:id)
  end

  def sign_in_as
    session[:user_id] = User.find(params[:id]).id
    redirect_to "/hr"
  end

  private

  def demo_only!
    head :not_found unless ENV["HR_LITE_DEMO"] == "1"
  end
end
