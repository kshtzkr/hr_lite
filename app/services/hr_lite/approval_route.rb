module HrLite
  # Drives one record through its flow: opens the first rung, advances when a
  # rung is satisfied, and reports when the whole thing is settled.
  #
  # It decides NOTHING about the subject itself. `Approvable` owns what
  # "approved" means for a leave request; this class only knows whose turn it
  # is. That split is why adding expenses later needs no change here.
  class ApprovalRoute
    Result = Struct.new(:outcome, :approval, keyword_init: true)

    def initialize(subject)
      @subject = subject
    end

    attr_reader :subject

    def flow = @flow ||= ApprovalFlow.for(subject.class.name)

    def routed? = flow.present?

    # Opens the first rung that has anybody on it. A rung whose rule resolves
    # to nobody — no manager recorded, say — is SKIPPED rather than left
    # waiting for a person who does not exist.
    def open!
      return Result.new(outcome: :unrouted) unless routed?

      flow.approval_steps.ordered.each do |step|
        approvers = step.approvers_for(subject)
        next skip!(step) if approvers.empty?

        create_rows(step, approvers)
        return Result.new(outcome: :pending)
      end

      # Every rung skipped: nobody in the flow can decide, so the request
      # carries itself. Better than a request that can never be answered.
      Result.new(outcome: :approved)
    end

    def pending_rows = Approval.pending.where(subject: subject)

    def current_position = pending_rows.minimum(:position)

    # Records one decision and works out what it means for the record.
    #
    #   :pending  — the rung still needs somebody
    #   :approved — every rung is satisfied
    #   :rejected — one refusal ends it
    #   :returned — sent back to the requester for correction
    def decide!(approval, status:, actor:, note: nil)
      approval.decide!(status: status, actor: actor, note: note)

      case status.to_s
      when "rejected", "returned"
        cancel_remaining!(approval.position)
        Result.new(outcome: status.to_sym, approval: approval)
      else
        advance_from(approval)
      end
    end

    def cancel_all!
      pending_rows.update_all(status: "cancelled", decided_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    private

    def advance_from(approval)
      rung = Approval.where(subject: subject).at_position(approval.position)
      # A unanimous rung waits for everybody; otherwise the first answer
      # settles it and the rest are stood down.
      if approval.step.unanimous && rung.pending.exists?
        return Result.new(outcome: :pending, approval: approval)
      end

      rung.pending.each { |other| other.decide!(status: "skipped", actor: nil) }
      open_next_after(approval.position) || Result.new(outcome: :approved, approval: approval)
    end

    def open_next_after(position)
      flow.approval_steps.ordered.each do |step|
        next if step.position <= position

        approvers = step.approvers_for(subject)
        next skip!(step) if approvers.empty?

        create_rows(step, approvers)
        return Result.new(outcome: :pending)
      end
      nil
    end

    def create_rows(step, approvers)
      approvers.uniq.each do |approver|
        Approval.create!(subject: subject, step: step, position: step.position,
                         approver_id: approver.id)
      end
    end

    # Nothing to record: a rung nobody occupies never happened. Returning nil
    # keeps `each`'s `next` readable at the call sites.
    def skip!(_step) = nil

    def cancel_remaining!(position)
      Approval.pending.where(subject: subject).where("position >= ?", position)
              .each { |row| row.decide!(status: "cancelled", actor: nil) }
    end
  end
end
