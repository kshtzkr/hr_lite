module HrLite
  module Admin
    class AppraisalsController < SuperadminController
      before_action :set_profile

      def new
        @appraisal = Appraisal.new(
          user_id: @profile.user_id,
          period_start: Date.current.beginning_of_year, period_end: Date.current
        )
      end

      def create
        @appraisal = Appraisal.new(appraisal_params.merge(
          user_id: @profile.user_id, reviewer_id: hr_current_user.id
        ))
        if @appraisal.save
          redirect_to admin_employee_path(@profile), notice: "Appraisal drafted — share when ready."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @appraisal = scoped.find(params[:id])
      end

      def update
        @appraisal = scoped.find(params[:id])
        if @appraisal.update(appraisal_params)
          redirect_to admin_employee_path(@profile), notice: "Appraisal updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def share
        appraisal = scoped.find(params[:id])
        appraisal.share!(actor: hr_current_user)
        redirect_to admin_employee_path(@profile), notice: "Appraisal shared with the employee."
      rescue ActiveRecord::RecordInvalid => e
        message = e.record.errors.full_messages.to_sentence.presence || "This appraisal was already shared."
        redirect_to admin_employee_path(@profile), alert: message
      end

      def destroy
        appraisal = scoped.find(params[:id])
        if appraisal.destroy
          redirect_to admin_employee_path(@profile), notice: "Draft appraisal removed.", status: :see_other
        else
          redirect_to admin_employee_path(@profile), status: :see_other,
                      alert: appraisal.errors.full_messages.to_sentence
        end
      end

      private

      def set_profile
        @profile = EmployeeProfile.find(params[:employee_id])
      end

      def scoped
        Appraisal.where(user_id: @profile.user_id)
      end

      def appraisal_params
        params.require(:appraisal).permit(
          :period_start, :period_end, :rating, :strengths, :improvements,
          :outcome, :effective_date, :new_designation
        )
      end
    end
  end
end
