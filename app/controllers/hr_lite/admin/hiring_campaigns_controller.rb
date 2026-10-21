module HrLite
  module Admin
    # Hiring drives: the list, one campaign's pipeline, and its sheet import.
    class HiringCampaignsController < ApplicationController
      FIELDS = %i[title position programme stipend ctc location schedule status].freeze

      before_action { hr_require_permission!("hiring.manage", scope: :all) }
      before_action :set_campaign, except: %i[index new create]

      def index
        @campaigns = paginate(HiringCampaign.newest_first)
        @counts = HiringCandidate.where(campaign_id: @campaigns.map(&:id)).group(:campaign_id, :stage).count
      end

      def show
        @stage = params[:stage].presence_in(HiringCandidate::STAGES)
        @campus = params[:campus].presence
        @stage_counts = @campaign.candidates.group(:stage).count
        @campuses = @campaign.candidates.where.not(campus: [ nil, "" ]).distinct.order(:campus).pluck(:campus)
        @candidates = paginate(@campaign.pipeline(stage: @stage, campus: @campus))
        @templates = HiringTemplate.alphabetical
        @attention = HiringMessage.joins(:candidate).where(hr_lite_hiring_candidates: { campaign_id: @campaign.id })
                                  .where(status: %w[failed unknown sending]).includes(:candidate, :template).limit(50)
      end

      # A new campaign starts from the last one's offer: HR edits what changed.
      def new
        @campaign = HiringCampaign.new(HiringCampaign.newest_first.first&.slice(*FIELDS.excluding(:title, :status)))
      end

      def create
        @campaign = HiringCampaign.new(campaign_params)
        return render(:new, status: :unprocessable_entity) unless @campaign.save

        redirect_to hr_lite.admin_hiring_campaign_path(@campaign), notice: "Campaign created. Upload the candidate sheet next."
      end

      def edit; end

      def update
        return render(:edit, status: :unprocessable_entity) unless @campaign.update(campaign_params)

        redirect_to hr_lite.admin_hiring_campaign_path(@campaign), notice: "Saved."
      end

      # GET: the upload form. POST with a file: the preview. POST with the
      # sealed rows and confirm: the import. Nothing is saved before confirm.
      def import
        return if request.get?

        rows = params[:sheet].present? ? read_sheet(params[:sheet]) : sealer.decrypt_and_verify(params[:rows].to_s)
        @import = HiringImport.new(@campaign, rows, picks: params.fetch(:picks, {}).permit!.to_h)
        if params[:confirm].present? && @import.import!
          counts = @import.counts
          return redirect_to hr_lite.admin_hiring_campaign_path(@campaign),
                             notice: "#{counts['create']} added, #{counts['update']} updated, #{counts['skip']} skipped."
        end
        @sealed = sealer.encrypt_and_sign(rows, expires_in: 1.hour)
        render :preview
      rescue ArgumentError => e
        redirect_to hr_lite.import_admin_hiring_campaign_path(@campaign), alert: e.message
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        redirect_to hr_lite.import_admin_hiring_campaign_path(@campaign), alert: "That preview expired. Upload the sheet again."
      rescue ActiveRecord::RecordNotUnique
        redirect_to hr_lite.import_admin_hiring_campaign_path(@campaign), alert: "Another import ran at the same time. Upload the sheet again."
      end

      private

      def set_campaign = @campaign = HiringCampaign.find(params[:id])
      def campaign_params = params.require(:hiring_campaign).permit(*FIELDS)

      def read_sheet(file)
        rows = HrLite.config.read_sheet.call(file.tempfile.path, file.original_filename)
        Array(rows).map { |row| Array(row).map { |cell| HiringImport.text(cell) } }
      rescue ArgumentError
        raise
      rescue StandardError
        raise ArgumentError, "That file could not be read. Save it as .xlsx or .csv with the headers in the first row."
      end

      # The previewed rows ride in the form, encrypted, so nothing touches disk.
      def sealer
        ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key("hr_lite.hiring_import", 32))
      end
    end
  end
end
