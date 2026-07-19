require "rails_helper"

# Regression: the slip PDF template is rendered by HOST code via
# config.render_pdf (e.g. the host's own ApplicationController.render), where
# the engine's helper modules are NOT in scope. The template must therefore
# depend only on assigns, models and POROs — this spec renders it through a
# bare ActionController::Base exactly like a host renderer would.
RSpec.describe "salary slip PDF template under a host renderer" do
  it "renders without engine helpers in scope" do
    leader = create(:user, :admin, email: "lead@x.test")
    HrLite.config.leadership_emails = [ "lead@x.test" ]
    profile = create(:employee_profile, pan_number: "ABCDE1234F", bank_name: "HDFC",
                                        bank_account_number: "1234567890")
    create(:salary_structure, user: profile.user)
    run = create(:payroll_run, period_month: Date.new(2027, 6, 1))
    run.compute!(actor: leader)
    slip = run.salary_slips.first

    html = ActionController::Base.render(
      template: "hr_lite/salary_slips/pdf",
      layout: "hr_lite/pdf",
      assigns: { slip: slip, profile: profile }
    )

    expect(html).to include("Salary slip")
      .and include("rupees")           # AmountInWords PORO, not a helper
      .and include("AB••••••4F")       # masked PAN from the model
      .and include("Provident fund")
  end
end

RSpec.describe HrLite::AmountInWords do
  it "spells Indian-system amounts" do
    expect(described_class.words(BigDecimal("369000"))).to eq("Three lakh sixty-nine thousand rupees")
    expect(described_class.words(BigDecimal("12345678"))).to eq("One crore twenty-three lakh forty-five thousand six hundred seventy-eight rupees")
    expect(described_class.words(0)).to eq("Zero rupees")
  end
end
