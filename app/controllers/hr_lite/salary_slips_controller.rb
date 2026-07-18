module HrLite
  # Employee surface: strictly own PUBLISHED slips — a foreign or
  # unpublished id 404s through the scoped relation, never 403s.
  class SalarySlipsController < ApplicationController
    def index
      @slips = paginate(own_published.recent_first)
    end

    def show
      @slip = own_published.find(params[:id])

      respond_to do |format|
        format.html
        format.pdf { send_slip_pdf(@slip) }
      end
    end

    private

    def own_published
      SalarySlip.published.where(user_id: hr_current_user.id)
    end

    def send_slip_pdf(slip)
      pdf = PdfRenderer.render(
        template: "hr_lite/salary_slips/pdf",
        assigns: { slip: slip, profile: slip.user_profile },
        cache_key: slip.pdf_cache_key
      )
      if pdf
        send_data pdf, filename: "salary-slip-#{slip.period_month.strftime('%Y-%m')}.pdf",
                       type: "application/pdf", disposition: "inline"
      else
        redirect_to salary_slip_path(slip),
                    alert: "PDF downloads are not configured on this install."
      end
    end
  end
end
