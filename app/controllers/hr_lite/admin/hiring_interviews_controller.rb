module HrLite
  module Admin
    # Interview rounds on the hiring mailbox's Google Calendar. The row is
    # written before Google is called, so an answer that never arrives still
    # leaves a record ("unknown") for HR to check.
    class HiringInterviewsController < ApplicationController
      LENGTHS = [ 30, 45, 60 ].freeze
      MAX_INTERVIEWERS = 10

      before_action { hr_require_permission!("hiring.manage", scope: :all) }
      before_action { @candidate = HiringCandidate.includes(:campaign).find(params[:hiring_candidate_id]) }
      before_action(except: :create) { @interview = @candidate.interviews.find(params[:id]) }
      before_action :require_calendar!

      def create
        return back(alert: "#{@candidate.stage_label} cannot be interviewed.") unless HiringCandidate::MOVES.fetch(@candidate.stage).include?("interview")
        return back(alert: "Pick a date and time in the future.") unless (starts, ends = slot)
        return back(alert: @interviewer_error) unless (guests = interviewers)

        round = @candidate.interviews.where(status: %w[scheduled unknown]).maximum(:round).to_i + 1
        @interview = @candidate.interviews.create!(round: round, starts_at: starts, ends_at: ends, interviewers: guests)
        ids = adapter.create_event(summary: "Interview: #{@candidate.campaign.position} (round #{round})",
                                   description: "#{@candidate.campaign.title}. Join with the Google Meet link in this invite.",
                                   attendee: @candidate.email, guests: guests, starts_at: starts, ends_at: ends)
        @interview.update!(status: "scheduled", event_id: ids[:event_id], meet_link: ids[:meet_link])
        @candidate.move_to!("interview", round: round)
        @candidate.log!("interview_scheduled", round: round, starts_at: starts.iso8601, with: guests.join(", ").presence)
        back(notice: "Invite sent for round #{round}#{" to the candidate and #{guests.size} interviewer#{'s' if guests.many?}" if guests.any?}.")
      rescue HrLite::HiringDeliveryUnknown, HrLite::HiringDeliveryFailed => e
        google_trouble(e, "interview_scheduled")
      end

      def update
        return back(alert: "Pick a date and time in the future.") unless (starts, ends = slot)
        adapter.update_event(event_id: @interview.event_id, starts_at: starts, ends_at: ends)
        @interview.update!(starts_at: starts, ends_at: ends)
        @candidate.log!("interview_rescheduled", round: @interview.round, starts_at: starts.iso8601)
        back(notice: "Round #{@interview.round} moved. Google told the candidate.")
      rescue HrLite::HiringDeliveryUnknown, HrLite::HiringDeliveryFailed => e
        google_trouble(e, "interview_rescheduled")
      end

      def destroy
        adapter.cancel_event(event_id: @interview.event_id) if @interview.event_id
        @interview.update!(status: "cancelled")
        @candidate.log!("interview_cancelled", round: @interview.round)
        back(notice: "Round #{@interview.round} cancelled. Google told the candidate.")
      rescue HrLite::HiringDeliveryUnknown, HrLite::HiringDeliveryFailed => e
        google_trouble(e, "interview_cancelled")
      end

      private

      def adapter = HrLite.config.hiring
      def back(**flash) = redirect_to(hr_lite.admin_hiring_candidate_path(@candidate), **flash)

      # Staff picked from the system plus any emails typed in, as one de-duplicated list.
      def interviewers
        staff = HrLite.active_employees.select { |u| Array(params[:interviewer_ids]).map(&:to_i).include?(u.id) }.map(&:email)
        typed = params[:interviewer_emails].to_s.split(/[\s,;]+/).map { |e| e.strip.downcase }.compact_blank
        bad = typed.reject { |e| e.match?(URI::MailTo::EMAIL_REGEXP) }
        all = (staff.map(&:downcase) + typed).uniq - [ @candidate.email ]
        @interviewer_error = if bad.any? then "Check these interviewer emails: #{bad.join(', ')}"
        elsif all.size > MAX_INTERVIEWERS then "Invite at most #{MAX_INTERVIEWERS} interviewers."
        end
        all unless @interviewer_error
      end

      def require_calendar!
        back(alert: "Connect the hiring mailbox before scheduling.") unless adapter&.sender&.dig(:ready)
      end

      def slot
        starts = Time.zone.parse("#{params[:date]} #{params[:time]}")
        return unless starts&.future?

        minutes = LENGTHS.include?(params[:minutes].to_i) ? params[:minutes].to_i : LENGTHS.first
        [ starts, starts + minutes.minutes ]
      rescue ArgumentError
        nil
      end

      def google_trouble(error, action)
        unknown = error.is_a?(HrLite::HiringDeliveryUnknown)
        @interview.update!(status: unknown ? "unknown" : "failed", error: error.message.to_s.truncate(200)) if action == "interview_scheduled"
        @candidate.log!("#{action}_#{unknown ? 'unknown' : 'failed'}", round: @interview.round)
        back(alert: unknown ? "Google did not confirm. Check the hiring calendar before trying again." : "Google refused: #{error.message}")
      end
    end
  end
end
