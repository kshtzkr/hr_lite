module HrLite
  # The six roles an install starts with. They are a STARTING POINT, not a
  # ladder in code: an install is expected to edit the grants, and `roles:seed`
  # never overwrites a role that already exists.
  #
  # Read the scopes as the interesting part. Manager and HR hold the same
  # leave.approve key — the difference between them is `team` and `all`, which
  # is the whole reason scope lives on the grant.
  module RoleSeeds
    # A method, not a constant: the keys are Role constants, and this file is
    # required while the gem loads, long before Active Record models exist.
    def self.definitions
      {
      Role::EMPLOYEE => {
        description: "Self-service only: own attendance, leave, documents and payslips.",
        grants: {
          "leave.request" => "self", "leave.view" => "self",
          "attendance.view" => "self", "payroll.view" => "self",
          "profile.view" => "self", "appraisal.view" => "self",
          "resignation.view" => "self", "document.view" => "self", "tax.view" => "self",
          "expense.claim" => "self", "benefit.view" => "self",
          "hr_request.raise" => "self", "policy.view" => "all", "asset.view" => "self"
        }
      },
      Role::MANAGER => {
        description: "Everything an employee has, plus their reports' attendance and leave.",
        grants: {
          "leave.request" => "self", "leave.view" => "team", "leave.approve" => "team",
          "attendance.view" => "team", "attendance.manage" => "team",
          "payroll.view" => "self", "profile.view" => "team",
          "appraisal.view" => "self", "resignation.view" => "self"
        }
      },
      Role::HR => {
        description: "Day-to-day operations for everyone: attendance, leave, holidays, tickets.",
        grants: {
          "leave.request" => "self", "leave.view" => "all", "leave.approve" => "all",
          "leave.manage" => "all", "attendance.view" => "all", "attendance.manage" => "all",
          "profile.view" => "all", "payroll.view" => "self",
          "appraisal.view" => "self", "resignation.view" => "all",
          "document.view" => "all", "tax.view" => "self",
          "expense.claim" => "self", "benefit.view" => "all", "benefit.manage" => "all",
          "hr_request.raise" => "self", "hr_request.manage" => "all", "policy.view" => "all",
          "asset.view" => "all", "asset.manage" => "all", "checklist.manage" => "all"
        }
      },
      Role::FINANCE => {
        description: "Payroll and pay data. No authority over people or policy.",
        grants: {
          "leave.request" => "self", "leave.view" => "self",
          "attendance.view" => "all", "profile.view" => "all",
          "payroll.view" => "all", "payroll.manage" => "all", "payroll.export" => "all",
          "salary.view" => "all", "salary.manage" => "all",
          "tax.view" => "all", "tax.manage" => "all",
          "expense.claim" => "self", "expense.approve" => "all", "expense.reimburse" => "all",
          "policy.view" => "all",
          "audit.view" => "all", "audit.view_money" => "all"
        }
      },
      Role::LEADERSHIP => {
        description: "People and policy for everyone — deliberately NOT pay.",
        grants: {
          "leave.request" => "self", "leave.view" => "all", "leave.approve" => "all",
          "leave.manage" => "all", "attendance.view" => "all", "attendance.manage" => "all",
          "profile.view" => "all", "profile.manage" => "all",
          "resignation.view" => "all", "resignation.manage" => "all",
          "settings.manage" => "all", "audit.view" => "all", "payroll.view" => "self",
          "document.view" => "all", "expense.approve" => "all", "benefit.manage" => "all",
          "hr_request.manage" => "all", "policy.view" => "all", "policy.manage" => "all",
          "asset.view" => "all", "asset.manage" => "all", "checklist.manage" => "all"
        }
      },
      Role::SUPER_ADMIN => {
        description: "Everything, including pay, appraisals and who holds which role.",
        grants: Permissions::KEYS.to_h { |key| [ key, "all" ] }
      }
      }.freeze
    end

    # Creates any role that does not exist yet and leaves every existing one
    # exactly as the install has tuned it — the same contract as the leave-type
    # seed. Returns the names it created.
    def self.call
      definitions.filter_map do |name, definition|
        next if Role.exists?(name: name)

        role = Role.create!(name: name, description: definition[:description], system: true)
        role.replace_grants!(definition[:grants])
        name
      end
    end
  end
end
