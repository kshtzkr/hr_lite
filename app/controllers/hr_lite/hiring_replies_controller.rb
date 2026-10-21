module HrLite
  # The candidate's own page from @interest_link: are they interested, which
  # day and 2-hour slot suits them, and a few yes/no questions. One reply each.
  class HiringRepliesController < ApplicationController
    # WHY no login: candidates have no account. The unguessable 24-character
    # token in their link is the key, and it opens only their own reply.
    skip_before_action :hr_authenticate!
    skip_before_action HrLite.config.authenticate_method, raise: false
    layout "hr_lite/public"
    rate_limit to: 10, within: 1.hour, only: :create, name: "hiring_reply",
               with: -> { redirect_to hr_lite.hiring_reply_path(params[:token]), alert: "Too many tries. Please try again in an hour." }

    before_action { @candidate = HiringCandidate.includes(:campaign).find_by!(interest_token: params[:token].to_s) }

    def show; end

    def create
      @candidate.reply!(interested: params[:interested].to_s, date: params[:date], slot: params[:slot], joining: params[:joining],
                        yes_no: params.permit(*HiringCandidate::YES_NO).to_h)
      redirect_to hr_lite.hiring_reply_path(@candidate.interest_token)
    rescue ArgumentError => e
      flash.now[:alert] = e.message
      render :show, status: :unprocessable_entity
    end
  end
end
