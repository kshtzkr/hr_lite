module HrLite
  # One promotion / role change. Creating it stamps the employee profile's
  # current designation and tells the host (so e.g. the CMS job title stays
  # in sync). Rows are the career timeline — never edited or deleted.
  class DesignationChange < ApplicationRecord
    include Audited

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :appraisal, optional: true
    belongs_to :created_by, class_name: HrLite.config.user_class, optional: true

    validates :to_designation, :effective_date, presence: true

    scope :timeline, -> { order(effective_date: :desc, id: :desc) }

    before_create :capture_from_designation
    after_create :apply_to_profile
    after_create :notify

    def readonly?
      persisted? && !destroyed?
    end

    private

    def capture_from_designation
      self.from_designation ||= EmployeeProfile.find_by(user_id: user_id)&.designation
    end

    def apply_to_profile
      profile = EmployeeProfile.find_by(user_id: user_id)
      profile&.update!(designation: to_designation)

      begin
        HrLite.config.on_designation_change.call(user, to_designation)
      rescue => e
        Rails.logger.error("[hr_lite] on_designation_change failed: #{e.class}: #{e.message}")
      end
    end

    def notify
      Notifications.publish(
        "promotion.recorded",
        title: "New role: #{to_designation}",
        body: "Effective #{effective_date.strftime('%d %b %Y')}.",
        path: "/career",
        bell_to: [ user ],
        email_to: [ user ]
      )
    end
  end
end
