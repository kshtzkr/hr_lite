module HrLite
  # One mailer, two generic responsive templates. Per-event content (heading,
  # body, detail lines, diff table) is assembled by the Notifications bus so
  # adding an event never means adding a template.
  class EventMailer < ApplicationMailer
    def event(to:, subject:, heading:, body: nil, lines: [], path: nil, link_url: nil)
      @heading = heading
      @body = body
      @lines = Array(lines)
      @cta_url = link_url.presence || HrLite::EventMailer.link_for(path)
      mail(to: to, from: HrLite.config.mailer_from, subject: subject)
    end

    def leadership(to:, subject:, heading:, body: nil, lines: [], diff: nil, path: nil, event: nil)
      @heading = heading
      @body = body
      @lines = Array(lines)
      @diff = diff.presence
      @event = event
      @cta_url = HrLite::EventMailer.link_for(path)
      mail(to: to, from: HrLite.config.mailer_from, subject: subject)
    end

    # Emails need absolute URLs; the engine can't know its public mount.
    # Hosts set config.public_url_base (e.g. "https://hr.example.com");
    # unset => emails simply carry no link button.
    def self.link_for(path)
      return nil if path.blank?

      HrLite.public_url(path)
    end
  end
end
