# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Integrations
    module Edi
      class MockTest < Minitest::Test
        def setup
          @edi = Mock.new
        end

        # -- check_eligibility --

        def test_check_eligibility_returns_fhir_coverage_eligibility_response
          request = Lakeraven::Fhir::CoverageEligibilityRequest.new(
            patient_dfn: "123", coverage_type: "medicaid",
            payer_id: "BCBS", subscriber_id: "1"
          )

          result = @edi.check_eligibility(request)

          assert_instance_of Lakeraven::Fhir::CoverageEligibilityResponse, result
          assert result.enrolled?
          assert_equal "123", result.patient_dfn
        end

        # -- submit_claim --

        def test_submit_claim_returns_fhir_claim_response
          claim = Lakeraven::Fhir::Claim.new(
            claim_type: "837P", patient_dfn: "123",
            diagnosis_codes: ["J06.9"]
          )

          result = @edi.submit_claim(claim)

          assert_instance_of Lakeraven::Fhir::ClaimResponse, result
          assert result.accepted?
          assert result.success?
          refute_nil result.claim_id
        end

        # -- check_claim_status --

        def test_check_claim_status_returns_fhir_claim_response
          result = @edi.check_claim_status("CLM-001")

          assert_instance_of Lakeraven::Fhir::ClaimResponse, result
          assert result.accepted?
          assert_equal "CLM-001", result.claim_id
          assert_equal 120_000, result.paid_amount_cents
        end

        # -- process_remittance --

        def test_process_remittance_returns_array_of_explanation_of_benefit
          results = @edi.process_remittance(claim_id: "CLM-001")

          assert_kind_of Array, results
          assert_equal 1, results.length
          eob = results.first
          assert_instance_of Lakeraven::Fhir::ExplanationOfBenefit, eob
          assert_equal "CLM-001", eob.claim_id
          assert_equal 120_000, eob.paid_amount_cents
          assert_equal 30_000, eob.patient_responsibility_cents
          refute_empty eob.adjustments
          refute_empty eob.service_lines
        end

        def test_process_remittance_adjustments_use_integer_cents
          results = @edi.process_remittance(claim_id: "CLM-001")
          adjustment = results.first.adjustments.first

          assert_equal "CO-45", adjustment[:reason_code]
          assert_equal 30_000, adjustment[:amount_cents]
          assert_kind_of Integer, adjustment[:amount_cents]
        end

        def test_process_remittance_service_lines_use_integer_cents
          results = @edi.process_remittance(claim_id: "CLM-001")
          line = results.first.service_lines.first

          assert_equal "99213", line[:procedure_code]
          assert_equal 15_000, line[:charged_cents]
          assert_equal 12_000, line[:paid_cents]
        end

        def test_process_remittance_accepts_string_reference
          results = @edi.process_remittance("REM-001")

          assert_kind_of Array, results
          assert_equal 1, results.length
          assert_equal "CLM-REM-001", results.first.claim_id
        end
      end
    end
  end
end
