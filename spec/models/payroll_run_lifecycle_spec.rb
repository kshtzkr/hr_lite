require "rails_helper"

RSpec.describe HrLite::PayrollRun do
  let(:actor) { create(:user, admin: true) }

  describe "#compute! status handling" do
    # The rescue used to sit at method level, so `raise_unless`'s own
    # exception was caught and the run was stamped "draft" — including a
    # published one, which then exposed the delete-draft control and
    # cascaded over every salary slip.
    %w[finalized published].each do |terminal|
      it "leaves a #{terminal} run untouched when compute is refused" do
        run = create(:payroll_run, status: terminal)

        expect { run.compute!(actor: actor) }.to raise_error(ActiveRecord::RecordInvalid)
        expect(run.reload.status).to eq(terminal)
      end
    end

    it "restores the previous status when the computation itself blows up" do
      run = create(:payroll_run, status: "review")
      allow(HrLite::PayrollRunProcessor).to receive(:call).and_raise("boom")

      expect { run.compute!(actor: actor) }.to raise_error("boom")
      expect(run.reload.status).to eq("review")
    end

    it "recovers a run stranded in processing by a killed process" do
      run = create(:payroll_run, status: "processing")

      expect(run.compute!(actor: actor)).to be(true)
      expect(run.reload.status).to eq("review")
    end
  end
end
