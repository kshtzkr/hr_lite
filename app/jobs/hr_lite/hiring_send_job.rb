module HrLite
  # Sends one queued hiring email through the host's mail adapter. The first
  # step claims the row, so a redelivered or parallel job finds it taken and
  # stops: a send is attempted at most once. A crash after the claim leaves
  # "sending", which the screens show as "check Gmail", never as "send again".
  # Adapter errors must not quote the recipient: their text is stored.
  class HiringSendJob < ApplicationJob
    queue_as :default

    def perform(message_id)
      return unless HiringMessage.where(id: message_id, status: "queued").update_all(status: "sending", updated_at: Time.current) == 1

      message = HiringMessage.find(message_id)
      HrLite::Current.set(actor: message.sent_by) { deliver(message) }
    end

    private

    def deliver(message)
      candidate = message.candidate
      adapter = HrLite.config.hiring
      sender = adapter&.sender
      return finish(message, "failed", error: "No sender mailbox is connected") unless sender&.dig(:ready)

      mail = HiringMerge.new(candidate, sender_name: sender[:name]).render(message.template)
      return finish(message, "failed", error: "Missing #{mail.missing.join(', ')}") if mail.missing.any?

      ids = adapter.send_email(to: candidate.email, subject: mail.subject, body: mail.body)
      finish(message, "sent", sent_at: Time.current, gmail_message_id: ids[:message_id], gmail_thread_id: ids[:thread_id])
      candidate.move_to!("invited") if candidate.stage == "imported"
    rescue HrLite::HiringDeliveryUnknown => e
      finish(message, "unknown", error: e.message.to_s.truncate(200))
    rescue HrLite::HiringDeliveryFailed => e
      finish(message, "failed", error: e.message.to_s.truncate(200))
    end

    def finish(message, status, **attributes)
      message.update!(status: status, **attributes)
      message.candidate.log!("email_#{status}", template: message.template.name)
    end
  end
end
