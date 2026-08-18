module HrLite
  # Tells people before a document lapses. A passport or a visa is somebody's
  # right to work, and the whole problem with an expiry date is finding out
  # about it late.
  #
  # Warns at 30 days and again at 7, rather than every day for a month.
  class DocumentExpiryJob < ApplicationJob
    WINDOWS = [ 30, 7 ].freeze

    def perform(today: Date.current)
      WINDOWS.each do |days|
        Document.where(expires_on: today + days).includes(:user).find_each do |document|
          Notifications.publish(
            "document.expiring",
            title: "#{document.title} expires in #{days} days",
            body: "#{HrLite.display_name(document.user)} — #{document.category.humanize}, " \
                  "expiring #{document.expires_on.strftime('%d %b %Y')}.",
            path: "/profile",
            bell_to: [ document.user ],
            email_to: [ document.user ],
            leadership: { title: "#{HrLite.display_name(document.user)}'s #{document.title} " \
                                 "expires in #{days} days" }
          )
        end
      end
    end
  end
end
