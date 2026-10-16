module HrLite
  module Admin
    # HR sees every home employees save, decides any still pending, and is
    # the only one who changes a person's homes once they have MAX_LIVE.
    # Coordinates are only shown here, inside attendance.view reach.
    class WorkLocationsController < BaseController
      def index
        @status = params[:status].presence_in(WorkLocation::STATUSES) || "pending"
        @locations = paginate(hr_scope(WorkLocation.where(status: @status), "attendance.view")
                                .includes(:user).order(created_at: :desc))
      end

      def approve
        decide("approved", params[:decision_note].to_s.strip.presence)
      end

      def reject
        note = params[:decision_note].to_s.strip
        return redirect_to admin_work_locations_path, alert: "A note is required to reject." if note.blank?

        decide("rejected", note)
      end

      # Past attendance keeps its own coordinates and place; nothing is rewritten.
      def remove
        location = hr_scope(WorkLocation.live, "attendance.manage").where.not(user_id: hr_current_user.id).find(params[:id])
        location.remove!(actor: hr_current_user)
        redirect_to admin_work_locations_path(status: "removed"), notice: "#{location.name} removed for #{HrLite.display_name(location.user)}."
      end

      private

      def decide(status, note)
        location = hr_scope(WorkLocation.all, "attendance.manage").where.not(user_id: hr_current_user.id).find(params[:id])
        location.decide!(status, actor: hr_current_user, note: note)
        begin
          Notifications.publish("work_location.#{status}", title: "WFH location #{status} — #{location.name}",
                                                          body: note, path: "/work_locations",
                                                          bell_to: [ location.user ], email_to: [ location.user ])
        rescue => e
          Rails.logger.error("[hr_lite] work location notification failed: #{e.class}: #{e.message}")
        end
        redirect_to admin_work_locations_path, notice: "Location #{status}."
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_work_locations_path, alert: "Only pending locations can be decided."
      end
    end
  end
end
