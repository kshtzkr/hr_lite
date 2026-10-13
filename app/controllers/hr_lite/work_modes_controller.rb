module HrLite
  # Employee switches their own mode. hr_current_user is the only subject.
  class WorkModesController < ApplicationController
    before_action { raise ActiveRecord::RecordNotFound unless HrLite.config.office_geofence }

    def create
      result = WorkModeSwitch.call(user: hr_current_user, mode: params[:mode], source: "employee", actor: hr_current_user,
                                   params: params.permit(:title, :client, :destination, :reason, :minutes, :until, :category, :crm_ref))
      if result.ok?
        redirect_to attendance_path, notice: "You are now: #{result.event.label}."
      else
        redirect_to attendance_path, alert: result.error
      end
    end

    # Lead type-ahead for the meeting forms; the host decides who sees what.
    def crm_search
      query = params[:q].to_s.strip
      hook = HrLite.config.crm_search
      leads = hook && query.length >= 2 ? Array(hook.call(hr_current_user, query)).first(20) : []
      render json: leads.map { |l| { id: l[:id].to_s, label: l[:label].to_s } }
    end

    # Ends the current break / busy / meeting early.
    def end_overlay
      WorkModeEvent.open.overlay.where(user_id: hr_current_user.id).find_each { |e| e.close!("ended") }
      redirect_to attendance_path, notice: "Back to work."
    end
  end
end
