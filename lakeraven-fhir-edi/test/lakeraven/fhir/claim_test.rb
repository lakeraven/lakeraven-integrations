# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Fhir
    class ClaimTest < Minitest::Test
      def test_initializes_with_lakeraven_attributes
        claim = Claim.new(
          claim_type: "837P",
          patient_dfn: "123",
          payer_id: "BCBS",
          subscriber_id: "SUB-1",
          patient_first_name: "Alice",
          patient_last_name: "Anderson",
          patient_dob: "1970-01-01",
          provider_npi: "1234567890",
          service_date: "2026-04-08",
          diagnosis_codes: ["J06.9"],
          procedure_codes: [{ code: "99213", units: 1, charge_cents: 15_000 }],
          total_charge_cents: 15_000
        )

        assert_equal "837P", claim.claim_type
        assert_equal "123", claim.patient_dfn
        assert_equal "BCBS", claim.payer_id
        assert_equal "SUB-1", claim.subscriber_id
        assert_equal "Alice", claim.patient_first_name
        assert_equal "Anderson", claim.patient_last_name
        assert_equal "1970-01-01", claim.patient_dob
        assert_equal "1234567890", claim.provider_npi
        assert_equal "2026-04-08", claim.service_date
        assert_equal ["J06.9"], claim.diagnosis_codes
        assert_equal 15_000, claim.total_charge_cents
      end

      def test_wraps_fhir_claim_resource
        claim = Claim.new(claim_type: "837P", patient_dfn: "123", diagnosis_codes: ["J06.9"])
        assert_instance_of ::FHIR::Claim, claim.__getobj__
      end

      def test_professional_and_institutional_helpers
        prof = Claim.new(claim_type: "837P", patient_dfn: "123")
        inst = Claim.new(claim_type: "837I", patient_dfn: "123")

        assert prof.professional?
        refute prof.institutional?
        assert inst.institutional?
        refute inst.professional?
      end

      def test_procedure_codes_accessor
        codes = [{ code: "99213", units: 1, charge_cents: 15_000 }]
        claim = Claim.new(claim_type: "837P", patient_dfn: "123", procedure_codes: codes)
        assert_equal codes, claim.procedure_codes
      end

      def test_revenue_codes_accessor
        codes = [{ code: "0250", description: "Pharmacy", charge_cents: 50_000 }]
        claim = Claim.new(claim_type: "837I", patient_dfn: "123", revenue_codes: codes)
        assert_equal codes, claim.revenue_codes
      end

      def test_to_fhir_returns_claim_resource_hash
        claim = Claim.new(claim_type: "837P", patient_dfn: "123", diagnosis_codes: ["J06.9"])
        fhir = claim.to_fhir
        assert_equal "Claim", fhir[:resourceType]
        assert_equal "Patient/123", fhir[:patient][:reference]
      end

      def test_to_json_produces_valid_fhir_json
        claim = Claim.new(claim_type: "837P", patient_dfn: "123")
        json = claim.to_json
        parsed = JSON.parse(json)
        assert_equal "Claim", parsed["resourceType"]
      end

      def test_defaults_id
        claim = Claim.new(claim_type: "837P", patient_dfn: "123")
        refute_nil claim.id
      end

      def test_place_of_service_defaults_to_11
        claim = Claim.new(claim_type: "837P", patient_dfn: "123")
        assert_equal "11", claim.place_of_service
      end
    end
  end
end
