module HrLite
  module Admin
    # Hiring emails HR writes once and sends to many, with a preview filled
    # for a real candidate.
    class HiringTemplatesController < ApplicationController
      before_action { hr_require_permission!("hiring.manage", scope: :all) }
      before_action(only: %i[edit update]) { @template = HiringTemplate.find(params[:id]) }
      # "Write with AI" posts the same form with ai=1 (formaction would break per-form CSRF tokens).
      rate_limit to: 20, within: 1.hour, only: %i[create update], if: -> { params[:ai].present? }, name: "hiring_ai_draft", by: -> { hr_current_user.id },
                 with: -> { redirect_to hr_lite.admin_hiring_templates_path, alert: "Twenty AI drafts an hour is the limit. Try again later." }

      def index = @templates = HiringTemplate.alphabetical
      def new = @template = HiringTemplate.new

      def create
        @template = HiringTemplate.new(template_params)
        return draft if params[:ai].present?
        return render(:new, status: :unprocessable_entity) unless @template.save

        redirect_to hr_lite.edit_admin_hiring_template_path(@template), notice: "Saved."
      end

      def edit = load_preview

      def update
        return draft if params[:ai].present?
        return load_preview && render(:edit, status: :unprocessable_entity) unless @template.update(template_params)

        redirect_to hr_lite.edit_admin_hiring_template_path(@template), notice: "Saved."
      end

      private

      # "Write with AI": rewrites what HR typed into a clean email that uses
      # only known @fields. Nothing is saved; HR reviews it, then saves.
      def draft
        @template.assign_attributes(template_params)
        apply_ai_draft
        @template.persisted? ? load_preview && render(:edit) : render(:new)
      end

      def apply_ai_draft
        out = HrLite.config.hiring.draft_email(text: "Subject: #{@template.subject}\n\n#{@template.body}", placeholders: HiringMerge::RESERVED)
        unknown = HiringMerge.tokens("#{out[:subject]} #{out[:body]}") - HiringMerge::RESERVED
        raise HrLite::HiringDeliveryFailed, "it used unknown fields (#{unknown.map { |t| "@#{t}" }.join(', ')})" if unknown.any?

        @template.assign_attributes(subject: out[:subject], body: out[:body])
        @template.name = out[:name] if @template.name.blank? && out[:name].present?
        AuditLog.record!(action: "hiring.ai_draft", subject: @template)
        flash.now[:notice] = "AI draft ready. Check it, then save."
      rescue HrLite::HiringDeliveryFailed, HrLite::HiringDeliveryUnknown => e
        flash.now[:alert] = "AI could not draft this: #{e.message}"
      end

      def load_preview
        @sample = HiringCandidate.includes(:campaign, :interviews).order(updated_at: :desc).limit(200).to_a
        @preview_for = @sample.find { |c| c.id == params[:candidate_id].to_i } || @sample.first
        return true unless @preview_for

        sender_name = HrLite.config.hiring&.sender&.dig(:name)
        @preview = HiringMerge.new(@preview_for, sender_name:, preview: true).render(@template)
        # Readiness across the previewed candidate's campaign: who a send would reach.
        @campaign_size = @preview_for.campaign.candidates.count
        @ready = @preview_for.campaign.candidates.includes(:campaign, :interviews).count { |c| HiringMerge.new(c, sender_name:, preview: true).render(@template).missing.empty? }
        true
      end

      def template_params = params.require(:hiring_template).permit(:name, :subject, :body)
    end
  end
end
