module HrLite
  # Slip PDF entry point. Host override first (earthly_vms plugs its cached
  # WickedPdf service in via config.render_pdf); otherwise a built-in
  # WickedPdf render when the gem is present; otherwise nil — the controller
  # explains that PDF is not configured rather than crashing.
  module PdfRenderer
    def self.render(template:, assigns:, cache_key: nil)
      if HrLite.config.render_pdf
        HrLite.config.render_pdf.call(template: template, assigns: assigns, cache_key: cache_key)
      elsif wicked_pdf_class
        html = HrLite::ApplicationController.render(
          template: template, assigns: assigns, layout: "hr_lite/pdf", formats: [ :html ]
        )
        wicked_pdf_class.new.pdf_from_string(html, page_size: "A4")
      end
    end

    # Seam for tests and for hosts that lazy-load wicked_pdf.
    def self.wicked_pdf_class
      defined?(WickedPdf) ? WickedPdf : nil
    end
  end
end
