module HrLite
  # Employee's own WFH locations. Scoping to hr_current_user is the
  # authorization; coordinates arrive only from the device capture.
  # Self-registered homes count at once; at MAX_LIVE only HR changes them.
  class WorkLocationsController < ApplicationController
    CAP_MESSAGE = "You have #{WorkLocation::MAX_LIVE} home locations. Ask HR to change one.".freeze

    before_action :refuse_at_cap, only: %i[activate remove]

    def index
      @locations = WorkLocation.live.where(user_id: hr_current_user.id).order(:created_at)
      @location = WorkLocation.new
    end

    def create
      @location = WorkLocation.new(params.permit(:name, :address, :lat, :lng, :accuracy_m)
                                         .merge(user_id: hr_current_user.id, status: "approved", decided_at: Time.current))
      saved = WorkLocation.transaction { HrLite.user_klass.lock.find(hr_current_user.id) && @location.save }
      unless saved
        @locations = WorkLocation.live.where(user_id: hr_current_user.id).order(:created_at)
        return render :index, status: :unprocessable_entity
      end

      @location.make_active! unless WorkLocation.active_for(hr_current_user.id)
      AuditLog.record!(action: "work_location.self_saved", subject: @location, actor: hr_current_user, changes: { "name" => @location.name })
      notify("work_location.requested", "#{HrLite.display_name(hr_current_user)} saved a home location: #{@location.name}",
             "/admin/work_locations", HrLite.admin_users)
      redirect_to work_locations_path, notice: "#{@location.name} saved as a home location."
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

    def refuse_at_cap
      return if WorkLocation.live.where(user_id: hr_current_user.id).count < WorkLocation::MAX_LIVE

      redirect_to work_locations_path, alert: CAP_MESSAGE
    end

    def notify(event, title, path, to)
      Notifications.publish(event, title: title, path: path, bell_to: to)
    rescue => e
      Rails.logger.error("[hr_lite] work location notification failed: #{e.class}: #{e.message}")
    end
  end
end
