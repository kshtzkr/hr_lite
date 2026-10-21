module HrLite
  module Admin
    # One candidate: what we know, every email and interview, the timeline,
    # and the decisions HR makes by hand.
    class HiringCandidatesController < ApplicationController
      # Invited and interview come from sending and scheduling, never a button.
      MANUAL = %w[interested not_interested selected rejected on_hold].freeze

      before_action { hr_require_permission!("hiring.manage", scope: :all) }
      before_action { @candidate = HiringCandidate.includes(:campaign).find(params[:id]) }

      def show
        @messages = @candidate.messages.includes(:template).order(:created_at)
        @interviews = @candidate.interviews.order(:round, :created_at)
        @timeline = @candidate.timeline.limit(100)
      end

      def stage
        to = params[:to].presence_in(MANUAL) or raise ArgumentError, "That is not a decision HR makes here."
        @candidate.move_to!(to, reason: params[:reason], note: params[:note])
        redirect_to hr_lite.admin_hiring_candidate_path(@candidate), notice: "Moved to #{@candidate.stage_label}."
      rescue ArgumentError => e
        redirect_to hr_lite.admin_hiring_candidate_path(@candidate), alert: e.message
      end
    end
  end
end
