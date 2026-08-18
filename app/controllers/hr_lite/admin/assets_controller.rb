module HrLite
  module Admin
    # Who has the laptop.
    class AssetsController < BaseController
      skip_before_action :require_operations_access!
      before_action :require_assets!

      def index
        @assets = paginate(Asset.order(:status, :name).includes(asset_assignments: :user))
        @outstanding = AssetAssignment.live.includes(:asset, :user)
      end

      def new
        @asset = Asset.new
      end

      def create
        @asset = Asset.new(asset_params)
        if @asset.save
          redirect_to admin_assets_path, notice: "#{@asset.name} added."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def assign
        asset = Asset.find(params[:id])
        user = HrLite.user_klass.find(params[:user_id])
        asset.assign_to!(user, actor: hr_current_user)
        redirect_to admin_assets_path, notice: "#{asset.name} given to #{HrLite.display_name(user)}."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_assets_path, alert: "#{asset.name} is already with somebody."
      end

      def take_back
        asset = Asset.find(params[:id])
        asset.return!(actor: hr_current_user, condition: params[:condition_note],
                      status: params[:status].presence_in(Asset::STATUSES) || "available")
        redirect_to admin_assets_path, notice: "#{asset.name} taken back."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_assets_path, alert: "#{asset.name} is not with anybody."
      end

      private

      def require_assets! = hr_require_permission!("asset.manage", scope: :all)

      def asset_params
        params.require(:asset).permit(:name, :category, :serial_number, :purchased_on, :notes)
      end
    end
  end
end
