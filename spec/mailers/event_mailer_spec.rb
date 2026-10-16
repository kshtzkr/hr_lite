require "rails_helper"

RSpec.describe HrLite::EventMailer do
  before { HrLite.config.company = -> { { name: "Acme Escapes", address: nil, logo_path: nil } } }

  describe "#event" do
    let(:mail) do
      described_class.event(to: "a@x.test", subject: "Leave approved", heading: "Leave approved",
                            body: "Enjoy!", lines: [ "3 days", "CL" ], path: "/leave_requests/1")
    end

    it "renders subject, from and both bodies" do
      HrLite.config.mailer_from = "people@acme.test"
      expect(mail.subject).to eq("Leave approved")
      expect(mail.from).to eq([ "people@acme.test" ])
      expect(mail.to).to eq([ "a@x.test" ])

      html = mail.html_part.body.to_s
      text = mail.text_part.body.to_s
      aggregate_failures do
        expect(html).to include("Leave approved").and include("Enjoy!").and include("3 days").and include("Acme Escapes")
        expect(text).to include("Leave approved").and include("- CL")
      end
    end

    # Document-branding rule: every email that leaves carries the logo image and a way to reach the company.
    it "carries the logo image and a contact line when the host gives them" do
      HrLite.config.company = -> { { name: "Acme Escapes", phone: "+91 80 1234 5678", email: "hr@acme.test",
                                     email_logo_url: "https://acme.test/logo.png" } }
      html = mail.html_part.body.to_s
      expect(html).to include(%(<img src="https://acme.test/logo.png" alt="Acme Escapes"), "Questions: +91 80 1234 5678 · hr@acme.test")
      expect(mail.text_part.body.to_s).to include("Questions: +91 80 1234 5678 · hr@acme.test")
    end

    it "includes a link button only when public_url_base is configured" do
      expect(mail.html_part.body.to_s).not_to include("Open in HR")

      HrLite.config.public_url_base = "https://hr.acme.test/"
      with_link = described_class.event(to: "a@x.test", subject: "S", heading: "H", path: "/kudos")
      expect(with_link.html_part.body.to_s).to include(%(href="https://hr.acme.test/kudos"))
    end
  end

  describe "#leadership" do
    it "renders the diff table to every leadership address" do
      mail = described_class.leadership(
        to: [ "l1@x.test", "l2@x.test" ], subject: "[HR] Policy changed", heading: "Policy changed",
        lines: [ "By Boss" ], diff: { "quota" => [ 12, 15 ], "pan_number" => "[changed]" },
        path: "/admin/audit_logs", event: "policy.changed"
      )

      expect(mail.to).to eq([ "l1@x.test", "l2@x.test" ])
      html = mail.html_part.body.to_s
      text = mail.text_part.body.to_s
      aggregate_failures do
        expect(html).to include("Quota").and include("12").and include("15")
        expect(html).to include("Pan number").and include("[changed]")
        expect(text).to include("Quota: 12 -> 15")
      end
    end
  end

  describe ".link_for" do
    it "joins base and path safely, nil without either" do
      expect(described_class.link_for("/x")).to be_nil
      HrLite.config.public_url_base = "https://hr.x.test"
      expect(described_class.link_for(nil)).to be_nil
      expect(described_class.link_for("/x")).to eq("https://hr.x.test/x")
    end
  end
end
