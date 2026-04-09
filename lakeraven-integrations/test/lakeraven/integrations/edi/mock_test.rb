# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Integrations
    module Edi
      class MockTest < Minitest::Test
        def setup
          @edi = Mock.new
        end

        def test_check_eligibility_returns_eligibility_response
          result = @edi.check_eligibility(
            payer_id: "BCBS",
            subscriber_id: "1",
            subscriber_first_name: "Alice",
            subscriber_last_name: "Anderson",
            subscriber_dob: "1970-01-01",
            provider_npi: "1234567890",
            service_type: "30"
          )

          assert_instance_of EligibilityResponse, result
          assert result.eligible
          assert result.covered?
          assert_equal "Mock Medicaid", result.payer_name
          assert_equal "MOCK-1", result.subscriber_id
          assert_includes result.service_types, "30"
        end

        def test_check_eligibility_defaults_service_type
          result = @edi.check_eligibility(subscriber_id: "X")
          assert_includes result.service_types, "30"
        end

        def test_submit_claim_returns_claim_response_with_provided_id
          result = @edi.submit_claim(claim_id: "CLM-TEST")

          assert_instance_of ClaimResponse, result
          assert result.accepted
          assert result.success?
          assert_equal "CLM-TEST", result.claim_id
          assert_empty result.errors
        end

        def test_submit_claim_generates_claim_id_when_not_provided
          result = @edi.submit_claim({})

          assert result.claim_id.start_with?("CLM-")
        end

        def test_check_claim_status_returns_status_response_with_integer_cents
          result = @edi.check_claim_status("CLM-001")

          assert_instance_of StatusResponse, result
          assert_equal "CLM-001", result.claim_id
          assert_equal "A1", result.status_code
          assert_equal Date.today, result.effective_date
          assert_equal 150_000, result.total_charge_cents
          assert_equal 120_000, result.paid_amount_cents
        end

        def test_process_remittance_returns_array_of_remittance_responses
          results = @edi.process_remittance(claim_id: "CLM-001")

          assert_kind_of Array, results
          assert_equal 1, results.length
          r = results.first
          assert_instance_of RemittanceResponse, r
          assert_equal "CLM-001", r.claim_id
          assert_equal 120_000, r.paid_amount_cents
          assert_equal 30_000, r.patient_responsibility_cents
          refute_empty r.adjustments
          refute_empty r.service_lines
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
          assert_kind_of Integer, line[:charged_cents]
          assert_kind_of Integer, line[:paid_cents]
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
