module HrLite
  module Admin
    # Hiring emails HR writes once and sends to many, with a preview filled
    # for a real candidate.
    class HiringTemplatesController < ApplicationController
      before_action { hr_require_permission!("hiring.manage", scope: :all) }
      before_action(only: %i[edit update]) { @template = HiringTemplate.find(params[:id]) }

      def index = @templates = HiringTemplate.alphabetical
      def new = @template = HiringTemplate.new

      def create
        @template = HiringTemplate.new(template_params)
        return render(:new, status: :unprocessable_entity) unless @template.save

        redirect_to hr_lite.edit_admin_hiring_template_path(@template), notice: "Saved."
      end

      def edit = load_preview

      def update
        return load_preview && render(:edit, status: :unprocessable_entity) unless @template.update(template_params)

        redirect_to hr_lite.edit_admin_hiring_template_path(@template), notice: "Saved."
      end

      private

      def load_preview
        @sample = HiringCandidate.includes(:campaign, :interviews).order(updated_at: :desc).limit(200).to_a
        @preview_for = @sample.find { |c| c.id == params[:candidate_id].to_i } || @sample.first
        @preview = HiringMerge.new(@preview_for, sender_name: HrLite.config.hiring&.sender&.dig(:name)).render(@template) if @preview_for
        true
      end

      def template_params = params.require(:hiring_template).permit(:name, :subject, :body)
    end
  end
end
