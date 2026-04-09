# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Integrations
    module Edi
      class BaseTest < Minitest::Test
        def setup
          @edi = Base.new
        end

        def test_check_eligibility_raises_not_implemented
          request = Lakeraven::Fhir::CoverageEligibilityRequest.new(
            patient_dfn: "123", coverage_type: "medicaid"
          )
          assert_raises(NotImplementedError) { @edi.check_eligibility(request) }
        end

        def test_submit_claim_raises_not_implemented
          claim = Lakeraven::Fhir::Claim.new(claim_type: "837P", patient_dfn: "123")
          assert_raises(NotImplementedError) { @edi.submit_claim(claim) }
        end

        def test_check_claim_status_raises_not_implemented
          assert_raises(NotImplementedError) { @edi.check_claim_status("CLM-001") }
        end

        def test_process_remittance_raises_not_implemented
          assert_raises(NotImplementedError) { @edi.process_remittance("REM-001") }
        end
      end
    end
  end
end
