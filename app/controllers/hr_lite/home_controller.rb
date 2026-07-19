module HrLite
  class HomeController < ApplicationController
    def index
      @latest_kudos = Kudo.recent.includes(:giver, kudo_mentions: :user).limit(3)
    end
  end
end
