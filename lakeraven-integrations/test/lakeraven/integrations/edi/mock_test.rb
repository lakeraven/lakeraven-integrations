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

        def test_process_remittance_pays_allowed_amount_when_claim_provided
          results = @edi.process_remittance(
            claim_id: "CLM-EXAMPLE",
            billed_amount_cents: 62_000,
            allowed_amount_cents: 16_344,
            procedure_code: "99204"
          )
          eob = results.first

          assert_equal "CLM-EXAMPLE", eob.claim_id
          # Pays the allowed (Medicare-Like Rate) amount, not more than billed
          assert_equal 16_344, eob.paid_amount_cents
          # PRC is payer of last resort -> no patient responsibility
          assert_equal 0, eob.patient_responsibility_cents
          # The difference is a single CO-45 contractual adjustment
          assert_equal 1, eob.adjustments.length
          assert_equal "CO-45", eob.adjustments.first[:reason_code]
          assert_equal 45_656, eob.adjustments.first[:amount_cents]
          # One service line echoing the claim
          line = eob.service_lines.first
          assert_equal "99204", line[:procedure_code]
          assert_equal 62_000, line[:charged_cents]
          assert_equal 16_344, line[:paid_cents]
        end

        # -- process_remittance: fail closed on invalid claim amounts --
        # A claim payload (carrying procedure_code and/or amount fields) must
        # never fall through to the canned remittance: bad money data has to
        # fail closed, not silently emit a $1,200 payment.

        def test_process_remittance_rejects_allowed_exceeding_billed
          # A real Medicare-Like Rate is never above the billed charge.
          error = assert_raises(ArgumentError) do
            @edi.process_remittance(
              claim_id: "CLM-INVERTED",
              billed_amount_cents: 16_344,
              allowed_amount_cents: 62_000,
              procedure_code: "99204"
            )
          end
          # Must reject rather than pay the (larger) allowed amount.
          refute_match(/1200|120000/, error.message)
        end

        def test_process_remittance_rejects_claim_payload_missing_amounts
          # procedure_code marks this as a claim payload; absent amounts must
          # reject, NOT return the canned $1,200 / $300 remittance.
          assert_raises(ArgumentError) do
            @edi.process_remittance(claim_id: "CLM-NOAMOUNTS", procedure_code: "99204")
          end
          assert_raises(ArgumentError) do
            @edi.process_remittance(
              claim_id: "CLM-NILBILLED",
              billed_amount_cents: nil,
              allowed_amount_cents: 16_344,
              procedure_code: "99204"
            )
          end
        end

        def test_process_remittance_rejects_non_numeric_amounts
          assert_raises(ArgumentError) do
            @edi.process_remittance(
              claim_id: "CLM-NAN",
              billed_amount_cents: "N/A",
              allowed_amount_cents: 16_344,
              procedure_code: "99204"
            )
          end
        end

        def test_process_remittance_rejects_negative_amounts
          assert_raises(ArgumentError) do
            @edi.process_remittance(
              claim_id: "CLM-NEG",
              billed_amount_cents: 62_000,
              allowed_amount_cents: -1,
              procedure_code: "99204"
            )
          end
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
