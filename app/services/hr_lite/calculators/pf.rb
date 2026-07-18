module HrLite
  module Calculators
    # Provident fund on earned basic. Employee 12%; employer 12% split into
    # EPS (8.33%, wage-capped) and EPF (remainder); EDLI + admin charges are
    # employer-cost lines. All contributions round to the nearest rupee.
    module Pf
      Result = Struct.new(:pf_wage, :employee, :employer_eps, :employer_epf,
                          :edli, :admin_charges, keyword_init: true)

      def self.call(basic_earned:, on_full_basic:, rates:)
        basic = Money.d(basic_earned)
        pf_wage = on_full_basic ? basic : [ basic, rates[:wage_ceiling] ].min

        employee = Money.round_rupee(pf_wage * rates[:employee_rate])
        employer_total = Money.round_rupee(pf_wage * rates[:employer_rate])
        eps_wage = [ pf_wage, rates[:eps_wage_ceiling] ].min
        eps = Money.round_rupee(eps_wage * rates[:eps_rate])
        eps = employer_total if eps > employer_total
        edli_wage = [ pf_wage, rates[:edli_ceiling] ].min

        Result.new(
          pf_wage: pf_wage,
          employee: employee,
          employer_eps: eps,
          employer_epf: employer_total - eps,
          edli: Money.round_rupee(edli_wage * rates[:edli_rate]),
          admin_charges: Money.round_rupee(pf_wage * rates[:admin_rate])
        )
      end
    end
  end
end
