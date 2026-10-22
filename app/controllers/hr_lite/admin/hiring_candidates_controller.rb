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
        @replies = @candidate.replies.responded.order(:round).with_attached_documents
        next_round = [ @candidate.round, *@interviews.select { |i| %w[scheduled unknown].include?(i.status) }.map(&:round) ].max + 1
        @next_reply = @replies.find { |r| r.round == next_round && r.preferred_slot }
      end

      # A document from the candidate's reply, streamed only to hiring.manage and audit-logged.
      def document
        attachment = ActiveStorage::Attachment.find_by!(id: params[:attachment_id], record_type: "HrLite::HiringReply",
                                                        record_id: @candidate.replies.select(:id))
        AuditLog.record!(action: "hiring.document_viewed", subject: @candidate, changes: { "attachment" => attachment.id })
        bytes = attachment.record.read_document(attachment)
        send_data bytes, filename: attachment.filename.to_s.split("--", 2).last, disposition: "attachment",
                         type: Marcel::MimeType.for(StringIO.new(bytes), name: attachment.filename.to_s)
      end

      # The full Aadhaar or PAN, shown once on this render, audit-logged; never stored in the session.
      def reveal
        reply = @candidate.replies.find(params[:reply_id])
        field = params[:field].presence_in(%w[aadhaar pan]) or raise ActiveRecord::RecordNotFound
        AuditLog.record!(action: "hiring.kyc_revealed", subject: @candidate, changes: { "field" => field, "round" => reply.round })
        @revealed = { reply.id => { field => (field == "aadhaar" ? reply.aadhaar_number : reply.pan_number) } }
        show
        render :show
      end

      # Selected / Rejected / On hold also send that decision's saved email. With
      # none saved yet, HR writes it first; the decision waits until it exists.
      def stage
        to = params[:to].presence_in(MANUAL) or raise ArgumentError, "That is not a decision HR makes here."
        raise ArgumentError, "#{@candidate.stage_label} cannot move to #{to.humanize}." unless HiringCandidate::MOVES.fetch(@candidate.stage).include?(to)

        template = HiringTemplate.for_decision(to)
        if HiringTemplate::PURPOSES.key?(to) && !template
          return redirect_to hr_lite.new_admin_hiring_template_path(purpose: to, candidate_id: @candidate.id),
                             alert: "Write the #{HiringTemplate::PURPOSES[to]} email first. Every #{HiringTemplate::PURPOSES[to]} click sends it."
        end
        raise ArgumentError, "Connect your Google account for hiring before sending decision emails." if template && !HrLite.config.hiring&.sender&.dig(:ready)

        @candidate.move_to!(to, reason: params[:reason], note: params[:note])
        if template && (message = HiringMessage.create_or_find_by!(candidate: @candidate, template: template) { |m| m.batch = SecureRandom.uuid; m.sent_by = hr_current_user }).previously_new_record?
          HiringSendJob.perform_later(message.id)
        end
        redirect_to hr_lite.admin_hiring_candidate_path(@candidate),
                    notice: "Moved to #{@candidate.stage_label}.#{" The #{template.name} email is on its way." if template}"
      rescue ArgumentError => e
        redirect_to hr_lite.admin_hiring_candidate_path(@candidate), alert: e.message
      end
    end
  end
end
