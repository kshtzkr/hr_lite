module HrLite
  # The candidate's own page for one interview round, from @round1_link …
  # @round3_link: their day and slot, round 1's interest questions, and from
  # round 2 their documents. One reply per link.
  class HiringRepliesController < ApplicationController
    # WHY no login: candidates have no account. The unguessable 24-character
    # token in their link is the key, and it opens only that one reply.
    skip_before_action :hr_authenticate!
    skip_before_action HrLite.config.authenticate_method, raise: false
    layout "hr_lite/public"
    rate_limit to: 10, within: 1.hour, only: :create, name: "hiring_reply",
               with: -> { redirect_to hr_lite.hiring_reply_path(params[:token]), alert: "Too many tries. Please try again in an hour." }

    before_action do
      @reply = HiringReply.includes(candidate: :campaign).find_by!(token: params[:token].to_s)
      @candidate = @reply.candidate
    end

    def show; end

    def create
      date, slot = params[:pick].to_s.split("|", 2) # one radio per free day + slot
      @reply.submit!(interested: params[:interested].to_s, date: date, slot: slot, joining: params[:joining],
                     yes_no: params.permit(*HiringReply::YES_NO.keys).to_h, alternate_phone: params[:alternate_phone].to_s.strip,
                     files: params.fetch(:documents, {}).permit(*HiringReply::DOCUMENTS.fetch(@reply.round, {}).keys).to_h,
                     kyc: params.permit(:aadhaar_number, :pan_number, :pan_pending, :no_salary_slips, :consent).to_h.symbolize_keys)
      redirect_to hr_lite.hiring_reply_path(@reply.token)
    rescue ArgumentError => e
      flash.now[:alert] = e.message
      render :show, status: :unprocessable_entity
    end
  end
end
