module HrLite
  module Admin
    class LeaveTypesController < LeadershipController
      def index
        @leave_types = LeaveType.order(:position, :id)
      end

      def new
        @leave_type = LeaveType.new
      end

      def create
        @leave_type = LeaveType.new(leave_type_params)
        if @leave_type.save
          redirect_to admin_leave_types_path, notice: "Leave type created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @leave_type = LeaveType.find(params[:id])
      end

      def update
        @leave_type = LeaveType.find(params[:id])
        if @leave_type.update(leave_type_params)
          redirect_to admin_leave_types_path, notice: "Leave type updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # Types with history cannot be destroyed — deactivate instead.
      def destroy
        leave_type = LeaveType.find(params[:id])
        if leave_type.destroy
          redirect_to admin_leave_types_path, notice: "Leave type removed.", status: :see_other
        else
          redirect_to admin_leave_types_path, status: :see_other,
                      alert: "This type has leave history — deactivate it instead."
        end
      end

      private

      def leave_type_params
        params.require(:leave_type)
              .permit(:name, :code, :color, :paid, :comp_off, :annual_quota, :accrual,
                      :carry_forward_cap, :active, :position)
      end
    end
  end
end
