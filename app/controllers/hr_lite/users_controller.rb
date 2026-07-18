module HrLite
  # Mention autocomplete source. Available to any signed-in staff member.
  class UsersController < ApplicationController
    def search
      users = HrLite.config.mentionable_users.call(params[:q].to_s)
      render json: users.map { |u| { value: u.id, text: HrLite.display_name(u) } }
    end
  end
end
