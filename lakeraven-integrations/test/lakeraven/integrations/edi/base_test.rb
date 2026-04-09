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
          assert_raises(NotImplementedError) { @edi.submit_claim({}) }
        end

        def test_check_claim_status_raises_not_implemented
          assert_raises(NotImplementedError) { @edi.check_claim_status("CLM-001") }
        end

        def test_process_remittance_raises_not_implemented
          assert_raises(NotImplementedError) { @edi.process_remittance({}) }
        end
      end

      class ResponseValueObjectsTest < Minitest::Test
        def test_claim_response_success_when_accepted
          response = ClaimResponse.new(
            accepted: true, claim_id: "C1", tracking_number: "T1",
            errors: [], raw_response: {}
          )
          assert response.success?
        end

        def test_claim_response_failure_when_rejected
          response = ClaimResponse.new(
            accepted: false, claim_id: "C1", tracking_number: "T1",
            errors: [{ code: "E1" }], raw_response: {}
          )
          refute response.success?
        end

        def test_status_response_has_integer_cent_fields
          response = StatusResponse.new(
            claim_id: "C1",
            status_code: "A1",
            status_description: "Received",
            effective_date: Date.new(2026, 1, 1),
            total_charge_cents: 150_000,
            paid_amount_cents: 120_000,
            raw_response: {}
          )
          assert_equal "C1", response.claim_id
          assert_equal "A1", response.status_code
          assert_equal 150_000, response.total_charge_cents
          assert_equal 120_000, response.paid_amount_cents
        end

        def test_remittance_response_has_integer_cent_fields
          response = RemittanceResponse.new(
            claim_id: "C1",
            paid_amount_cents: 100_00,
            patient_responsibility_cents: 20_00,
            adjustments: [{ reason_code: "CO-45", amount_cents: 50_00, description: "test" }],
            service_lines: [{ procedure_code: "99213", charged_cents: 150_00, paid_cents: 120_00 }],
            raw_response: {}
          )
          assert_equal "C1", response.claim_id
          assert_equal 10_000, response.paid_amount_cents
          assert_equal 2_000, response.patient_responsibility_cents
          assert_equal 5_000, response.adjustments.first[:amount_cents]
          assert_equal 15_000, response.service_lines.first[:charged_cents]
          assert_equal 12_000, response.service_lines.first[:paid_cents]
        end
      end
    end
  end
end
