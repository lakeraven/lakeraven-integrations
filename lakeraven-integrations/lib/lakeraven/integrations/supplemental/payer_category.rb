# frozen_string_literal: true

module Lakeraven
  module Integrations
    module Supplemental
      # The UDS payer-category vocabulary. Payer category is NOT a
      # supplemental attribute Observation — it rides as FHIR::Coverage
      # resources returned by DataReader::Base#patient_coverages, with
      # +Coverage.type.coding+ = [{system: CODE_SYSTEM, code: <category>}].
      module PayerCategory
        # Internal code system URI for Coverage.type codings.
        CODE_SYSTEM = "https://terminology.lakeraven.com/CodeSystem/uds-payer-category"

        ALL = %w[medicaid medicare private uninsured other-public].freeze
      end
    end
  end
end
