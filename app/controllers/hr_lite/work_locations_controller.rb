module HrLite
  # Employee's own WFH locations. Scoping to hr_current_user is the
  # authorization; coordinates arrive only from the device capture.
  class WorkLocationsController < ApplicationController
    def index
      @locations = WorkLocation.live.where(user_id: hr_current_user.id).order(:created_at)
      @location = WorkLocation.new
    end

    def create
      @location = WorkLocation.new(params.permit(:name, :address, :lat, :lng, :accuracy_m)
                                         .merge(user_id: hr_current_user.id, status: "pending"))
      saved = WorkLocation.transaction { HrLite.user_klass.lock.find(hr_current_user.id) && @location.save }
      unless saved
        @locations = WorkLocation.live.where(user_id: hr_current_user.id).order(:created_at)
        return render :index, status: :unprocessable_entity
      end

      AuditLog.record!(action: "work_location.requested", subject: @location, actor: hr_current_user, changes: { "name" => @location.name })
      notify("work_location.requested", "#{HrLite.display_name(hr_current_user)} registered a WFH location: #{@location.name}",
             "/admin/work_locations", HrLite.admin_users)
      redirect_to work_locations_path, notice: "Location sent to HR for approval."
    end

    def activate
      location = WorkLocation.approved.where(user_id: hr_current_user.id).find(params[:id])
      location.make_active!
      redirect_to work_locations_path, notice: "#{location.name} is now your WFH location."
    end

    def remove
      WorkLocation.live.where(user_id: hr_current_user.id).find(params[:id]).remove!(actor: hr_current_user)
      redirect_to work_locations_path, notice: "Location removed."
    end

    private

    def notify(event, title, path, to)
      Notifications.publish(event, title: title, path: path, bell_to: to)
    rescue => e
      Rails.logger.error("[hr_lite] work location notification failed: #{e.class}: #{e.message}")
    end
  end
end
