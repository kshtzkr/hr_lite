module HrLite
  module Admin
    class HolidaysController < LeadershipController
      def index
        year = params[:year].to_i
        @year = year.between?(2000, 2100) ? year : Date.current.year
        @holidays = Holiday.includes(:office_location).where(date: Date.new(@year, 1, 1)..Date.new(@year, 12, 31)).order(:date)
        @holiday = Holiday.new
        @offices = OfficeLocation.order(:name).pluck(:name, :id)
      end

      def create
        @holiday = Holiday.new(holiday_params)
        if @holiday.save
          announce("Holiday added: #{@holiday.name} on #{@holiday.date.strftime('%a %d %b %Y')}", @holiday.office_location_id)
          redirect_to admin_holidays_path(year: @holiday.date.year), notice: "Holiday added."
        else
          redirect_to admin_holidays_path, alert: @holiday.errors.full_messages.to_sentence
        end
      end

      def update
        holiday = Holiday.find(params[:id])
        if holiday.update(holiday_params)
          redirect_to admin_holidays_path(year: holiday.date.year), notice: "Holiday updated."
        else
          redirect_to admin_holidays_path, alert: holiday.errors.full_messages.to_sentence
        end
      end

      def destroy
        holiday = Holiday.find(params[:id])
        holiday.destroy!
        redirect_to admin_holidays_path(year: holiday.date.year),
                    notice: "Holiday removed.", status: :see_other
      end

      # Bulk paste: one "YYYY-MM-DD, Name[, optional]" per line, all for the
      # chosen office (blank = every office). Reports per-line problems, skips
      # duplicates silently.
      def bulk_create
        office_id = OfficeLocation.find_by(id: params[:office_location_id])&.id
        created = 0
        problems = []

        params[:lines].to_s.each_line.with_index(1) do |line, number|
          line = line.strip
          next if line.blank?

          date_part, name_part, flag = line.split(",", 3).map { |part| part.to_s.strip }
          date = Date.strptime(date_part.to_s, "%Y-%m-%d") rescue nil
          if date.nil? || name_part.blank?
            problems << "Line #{number}: expected YYYY-MM-DD, Name"
            next
          end
          next if Holiday.exists?(date: date, office_location_id: office_id)

          Holiday.create!(date: date, name: name_part, optional: flag.to_s.casecmp?("optional"), office_location_id: office_id)
          created += 1
        end

        announce("#{created} holiday#{'s' unless created == 1} added to the calendar", office_id) if created.positive?
        message = "#{created} holiday#{'s' unless created == 1} added."
        message += " Problems: #{problems.join('; ')}" if problems.any?
        redirect_to admin_holidays_path, problems.any? ? { alert: message } : { notice: message }
      end

      private

      # An office's holiday goes to that office's people; an all-office one to everyone.
      def announce(title, office_id)
        staff = HrLite.active_employees
        if office_id
          in_office = EmployeeProfile.where(office_location_id: office_id).pluck(:user_id).to_set
          staff = staff.select { |u| in_office.include?(u.id) }
        end
        Notifications.publish("holiday.published", title: title, path: "/holidays", bell_to: staff, email_to: staff)
      end

      def holiday_params
        params.require(:holiday).permit(:date, :name, :optional, :office_location_id)
      end
    end
  end
end
