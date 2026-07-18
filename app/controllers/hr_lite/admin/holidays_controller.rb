module HrLite
  module Admin
    class HolidaysController < LeadershipController
      def index
        year = params[:year].to_i
        @year = year.between?(2000, 2100) ? year : Date.current.year
        @holidays = Holiday.where(date: Date.new(@year, 1, 1)..Date.new(@year, 12, 31)).order(:date)
        @holiday = Holiday.new
      end

      def create
        @holiday = Holiday.new(holiday_params)
        if @holiday.save
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

      # Bulk paste: one "YYYY-MM-DD, Name[, optional]" per line. Reports
      # per-line problems, skips duplicates silently.
      def bulk_create
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
          next if Holiday.exists?(date: date)

          Holiday.create!(date: date, name: name_part, optional: flag.to_s.casecmp?("optional"))
          created += 1
        end

        message = "#{created} holiday#{'s' unless created == 1} added."
        message += " Problems: #{problems.join('; ')}" if problems.any?
        redirect_to admin_holidays_path, problems.any? ? { alert: message } : { notice: message }
      end

      private

      def holiday_params
        params.require(:holiday).permit(:date, :name, :optional)
      end
    end
  end
end
