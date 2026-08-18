module HrLite
  # An employee's own documents, and the download itself.
  #
  # The FILE is the sensitive part, so every read goes through
  # `Document#readable_by?` rather than through the scope that found the row.
  # A passport is not a payslip: HR can see that one exists without being
  # handed the scan.
  class DocumentsController < ApplicationController
    def index
      @documents = Document.for_user(hr_current_user).recent_first
      @document = Document.new
      @expiring = @documents.select { |d| d.expires_on && d.expires_on <= 60.days.from_now.to_date }
    end

    def create
      @document = Document.new(document_params)
      @document.user_id = hr_current_user.id
      @document.uploaded_by_id = hr_current_user.id

      if @document.save
        redirect_to documents_path, notice: "#{@document.title} uploaded."
      else
        @documents = Document.for_user(hr_current_user).recent_first
        @expiring = []
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      document = Document.for_user(hr_current_user).find(params[:id])
      # A verified identity document is evidence HR acted on; removing it
      # quietly would leave their verification pointing at nothing.
      if document.verified?
        return redirect_to documents_path, status: :see_other,
                           alert: "#{document.title} has been verified — ask HR to replace it."
      end

      document.destroy!
      redirect_to documents_path, notice: "#{document.title} removed.", status: :see_other
    end

    # The one place a file leaves the building. Scoped by nothing — the
    # permission check is the row's own, because a document may be readable
    # by its owner, by HR, or by nobody but the money tier.
    def download
      document = Document.find(params[:id])
      unless document.readable_by?(hr_current_user)
        raise ActiveRecord::RecordNotFound
      end

      AuditLog.record!(
        action: "document.downloaded", subject: document, actor: hr_current_user,
        changes: { "title" => document.title, "category" => document.category,
                   "owner" => HrLite.display_name(document.user) }
      )
      # rails_blob_path, not url_for: an engine controller has no default
      # host and url_for(attachment) raises without one.
      redirect_to Rails.application.routes.url_helpers.rails_blob_path(
        document.file, disposition: "attachment", only_path: true
      ), allow_other_host: false
    end

    private

    def document_params
      params.require(:document).permit(:category, :title, :reference_number, :issued_on, :expires_on, :file)
    end
  end
end
