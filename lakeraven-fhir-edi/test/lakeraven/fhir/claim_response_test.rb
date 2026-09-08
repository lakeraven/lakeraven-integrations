# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Fhir
    class ClaimResponseTest < Minitest::Test
      def test_accepted_claim_response
        response = ClaimResponse.new(
          accepted: true,
          claim_id: "CLM-001",
          tracking_number: "TRK-001",
          patient_dfn: "123"
        )

        assert response.accepted?
        assert response.success?
        assert_equal "CLM-001", response.claim_id
        assert_equal "TRK-001", response.tracking_number
        assert_empty response.errors
      end

      def test_rejected_claim_response
        response = ClaimResponse.new(
          accepted: false,
          claim_id: nil,
          errors: [{ code: "REJ01", message: "Invalid subscriber" }],
          patient_dfn: "123"
        )

        refute response.accepted?
        refute response.success?
        assert_equal 1, response.errors.length
      end

      def test_wraps_fhir_claim_response_resource
        response = ClaimResponse.new(accepted: true, claim_id: "CLM-001", patient_dfn: "123")
        assert_instance_of ::FHIR::ClaimResponse, response.__getobj__
      end

      def test_to_fhir_returns_claim_response_hash
        response = ClaimResponse.new(accepted: true, claim_id: "CLM-001", patient_dfn: "123")
        fhir = response.to_fhir
        assert_equal "ClaimResponse", fhir[:resourceType]
      end

      def test_to_json_produces_valid_fhir_json
        response = ClaimResponse.new(accepted: true, claim_id: "CLM-001", patient_dfn: "123")
        parsed = JSON.parse(response.to_json)
        assert_equal "ClaimResponse", parsed["resourceType"]
      end

      def test_defaults_id
        response = ClaimResponse.new(accepted: true, patient_dfn: "123")
        refute_nil response.id
      end

      def test_paid_amount_cents
        response = ClaimResponse.new(
          accepted: true, claim_id: "CLM-001", patient_dfn: "123",
          paid_amount_cents: 120_000
        )
        assert_equal 120_000, response.paid_amount_cents
      end
    end
  end
end
