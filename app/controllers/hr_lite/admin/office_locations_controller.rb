module HrLite
  module Admin
    class OfficeLocationsController < LeadershipController
      def index
        @office_locations = OfficeLocation.order(:name)
      end

      def new
        @office_location = OfficeLocation.new
      end

      def create
        @office_location = OfficeLocation.new(office_location_params)
        if @office_location.save
          redirect_to admin_office_locations_path, notice: "Office added."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @office_location = OfficeLocation.find(params[:id])
      end

      def update
        @office_location = OfficeLocation.find(params[:id])
        if @office_location.update(office_location_params)
          redirect_to admin_office_locations_path, notice: "Office updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        OfficeLocation.find(params[:id]).destroy!
        redirect_to admin_office_locations_path, notice: "Office removed.", status: :see_other
      end

      private

      def office_location_params
        params.require(:office_location).permit(:name, :lat, :lng, :radius_m, :active)
      end
    end
  end
end
