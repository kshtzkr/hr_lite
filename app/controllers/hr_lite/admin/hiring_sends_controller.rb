module HrLite
  module Admin
    # Bulk email: a confirm page that says exactly who gets it and who is
    # left out (and why), then one queued job per recipient, spaced out.
    class HiringSendsController < ApplicationController
      SPACING = 3.seconds

      before_action { hr_require_permission!("hiring.manage", scope: :all) }
      rate_limit to: 10, within: 1.hour, only: :create, name: "hiring_send", by: -> { hr_current_user.id },
                 with: -> { redirect_to hr_lite.admin_hiring_campaigns_path, alert: "Ten sends in an hour is the limit. Try again later." }

      def new
        load_recipients
      end

      def create
        load_recipients
        unless @sender&.dig(:ready)
          return redirect_to hr_lite.admin_hiring_campaign_path(@campaign), alert: "Connect the hiring mailbox before sending."
        end

        batch = SecureRandom.uuid
        queued = @recipients.filter_map do |candidate|
          HiringMessage.create!(candidate: candidate, template: @template, batch: batch, sent_by: hr_current_user)
        rescue ActiveRecord::RecordNotUnique
          nil # already queued by another click
        end
        queued.each_with_index { |message, i| HiringSendJob.set(wait: SPACING * i).perform_later(message.id) }
        AuditLog.record!(action: "hiring.batch", subject: @campaign,
                         changes: { "template" => @template.name, "recipients" => queued.size, "batch" => batch })
        redirect_to hr_lite.admin_hiring_campaign_path(@campaign), notice: "#{queued.size} emails queued from #{@sender[:email]}."
      end

      # Only a definite failure is sent again; "unknown" may already be in Gmail.
      def retry
        message = HiringMessage.find(params[:id])
        if message.status == "failed"
          message.update!(status: "queued", error: nil, sent_by: hr_current_user)
          HiringSendJob.perform_later(message.id)
        end
        redirect_to hr_lite.admin_hiring_campaign_path(message.candidate.campaign_id), notice: "Queued again."
      end

      private

      # Recomputed on every request from the ids: the confirm page is never trusted.
      def load_recipients
        @campaign = HiringCampaign.find(params[:hiring_campaign_id])
        @template = HiringTemplate.find(params[:template_id])
        @sender = HrLite.config.hiring&.sender
        scope = params[:all].present? ? @campaign.pipeline(stage: params[:stage], campus: params[:campus], replied: params[:replied]) : @campaign.pipeline.where(id: Array(params[:candidate_ids]))
        already = HiringMessage.where(template: @template, candidate_id: scope.select(:id)).pluck(:candidate_id).to_set
        @recipients, @left_out = [], []
        scope.includes(:campaign, :interviews).each do |candidate|
          missing = HiringMerge.new(candidate, sender_name: @sender&.dig(:name)).render(@template).missing
          reason = already.include?(candidate.id) ? "already sent this template" : (missing.join(", ") if missing.any?)
          reason ? @left_out << [ candidate, reason ] : @recipients << candidate
        end
      end
    end
  end
end
