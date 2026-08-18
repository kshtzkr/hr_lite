module HrLite
  module Admin
    # HR's side: whose documents are missing, and verifying the ones that
    # arrived. Reaching a person's list is `document.view`; opening the file
    # still goes through the row's own visibility.
    class DocumentsController < BaseController
      skip_before_action :require_operations_access!
      before_action :require_document_access!

      def index
        @category = params[:category].presence
        scope = hr_scope(Document.includes(:user).recent_first, "document.view")
        scope = scope.where(category: @category) if @category
        @pending = scope.where(verification: "pending").limit(50).to_a
        @documents = paginate(scope)
        @categories = Document.distinct.order(:category).pluck(:category)
      end

      def show
        @employee = HrLite.user_klass.find(params[:user_id])
        hr_require_reach!("document.view", @employee)
        @documents = Document.for_user(@employee).recent_first
        @missing = Document::SENSITIVE_CATEGORIES - @documents.map(&:category)
      end

      def verify
        document = find_manageable
        document.verify!(actor: hr_current_user, note: params[:note])
        redirect_back fallback_location: admin_documents_path,
                      notice: "#{document.title} verified."
      end

      def reject
        document = find_manageable
        note = params[:note].to_s.strip
        if note.blank?
          return redirect_back fallback_location: admin_documents_path,
                               alert: "Say what is wrong with it — the employee has to re-upload."
        end

        document.reject!(actor: hr_current_user, note: note)
        redirect_back fallback_location: admin_documents_path, notice: "#{document.title} rejected."
      end

      private

      def require_document_access!
        hr_require_permission!("document.view", scope: :team)
      end

      # You may verify a document you can OPEN. Attesting to a scan you are
      # not allowed to look at is not verification, and the row's visibility
      # is what keeps an Aadhaar with the money tier rather than with
      # whoever happens to run HR.
      def find_manageable
        document = Document.find(params[:id])
        raise ActiveRecord::RecordNotFound unless document.readable_by?(hr_current_user)

        document
      end
    end
  end
end
