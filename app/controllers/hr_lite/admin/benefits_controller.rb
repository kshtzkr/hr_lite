module HrLite
  module Admin
    # Who is covered by what. Before this screen nothing created a benefit,
    # so every employee's /benefits page said "not enrolled".
    class BenefitsController < BaseController
      skip_before_action :require_operations_access!
      before_action :require_benefits!

      def index
        @benefits = Benefit.order(:name)
        @enrolments = paginate(BenefitEnrolment.where(ended_on: nil).includes(:benefit, :user).order(:enrolled_on))
      end

      def new
        @benefit = Benefit.new
      end

      def create
        @benefit = Benefit.new(benefit_params)
        if @benefit.save
          redirect_to admin_benefits_path, notice: "#{@benefit.name} added."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def enrol
        benefit = Benefit.find(params[:id])
        user = HrLite.user_klass.find(params[:user_id])
        benefit.benefit_enrolments.create!(user_id: user.id, enrolled_on: params[:enrolled_on].presence || Date.current,
                                           dependants: params[:dependants].presence || 0)
        redirect_to admin_benefits_path, notice: "#{HrLite.display_name(user)} enrolled in #{benefit.name}."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_benefits_path, alert: e.record.errors.full_messages.to_sentence
      end

      # Ends cover rather than deleting the row: who was covered when is
      # the record an insurance claim gets checked against.
      def unenrol
        enrolment = Benefit.find(params[:id]).benefit_enrolments.find_by!(user_id: params[:user_id], ended_on: nil)
        enrolment.update!(ended_on: params[:ended_on].presence || Date.current)
        redirect_to admin_benefits_path, notice: "Cover ended for #{HrLite.display_name(enrolment.user)}."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_benefits_path, alert: e.record.errors.full_messages.to_sentence
      end

      private

      def require_benefits! = hr_require_permission!("benefit.manage", scope: :all)

      def benefit_params
        params.require(:benefit).permit(:name, :kind, :provider, :policy_number, :coverage, :employer_premium,
                                        :employee_premium, :effective_from, :expires_on, :notes)
      end
    end
  end
end
