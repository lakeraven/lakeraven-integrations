# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Fhir
    class CoverageEligibilityRequestTest < Minitest::Test
      # -- Initialization --

      def test_assigns_default_id
        request = CoverageEligibilityRequest.new(patient_dfn: "123", coverage_type: "medicaid")
        refute_nil request.id
        assert_match(/\A[0-9a-f-]{36}\z/, request.id)
      end

      def test_sets_default_created_at
        request = CoverageEligibilityRequest.new(patient_dfn: "123", coverage_type: "medicaid")
        refute_nil request.created_at
      end

      def test_sets_default_service_date_to_today
        request = CoverageEligibilityRequest.new(patient_dfn: "123", coverage_type: "medicaid")
        assert_equal Date.current, request.service_date
      end

      def test_defaults_purpose_to_benefits
        request = CoverageEligibilityRequest.new(patient_dfn: "123", coverage_type: "medicaid")
        assert_equal "benefits", request.purpose
      end

      def test_preserves_explicit_service_date
        date = Date.new(2026, 1, 15)
        request = CoverageEligibilityRequest.new(
          patient_dfn: "123", coverage_type: "medicaid", service_date: date
        )
        assert_equal date, request.service_date
      end

      # -- Validations --

      def test_requires_patient_dfn
        request = CoverageEligibilityRequest.new(coverage_type: "medicaid")
        refute request.valid?
        assert_includes request.errors[:patient_dfn], "can't be blank"
      end

      def test_requires_coverage_type
        request = CoverageEligibilityRequest.new(patient_dfn: "123")
        refute request.valid?
        assert_includes request.errors[:coverage_type], "can't be blank"
      end

      def test_rejects_invalid_coverage_type
        request = CoverageEligibilityRequest.new(patient_dfn: "123", coverage_type: "made_up")
        refute request.valid?
        assert_includes request.errors[:coverage_type], "is not a valid coverage type"
      end

      def test_accepts_valid_coverage_types
        %w[medicare_a medicare_b medicare_d medicaid private_insurance
           va_benefits workers_comp auto_insurance state_program tribal_program].each do |type|
          request = CoverageEligibilityRequest.new(patient_dfn: "123", coverage_type: type)
          assert request.valid?, "Expected #{type} to be valid"
        end
      end

      # -- FHIR serialization --

      def test_to_fhir_returns_coverage_eligibility_request_resource
        request = CoverageEligibilityRequest.new(
          patient_dfn: "123",
          coverage_type: "medicaid",
          service_date: Date.new(2026, 4, 8)
        )
        fhir = request.to_fhir

        assert_equal "CoverageEligibilityRequest", fhir[:resourceType]
        assert_equal request.id, fhir[:id]
        assert_equal "active", fhir[:status]
        assert_equal ["benefits"], fhir[:purpose]
        assert_equal "Patient/123", fhir[:patient][:reference]
        assert_equal "2026-04-08", fhir[:servicedDate]
      end

      def test_to_fhir_includes_insurer_reference
        request = CoverageEligibilityRequest.new(patient_dfn: "123", coverage_type: "medicaid")
        insurer = request.to_fhir[:insurer]

        assert_equal "Organization/StateMedicaid", insurer[:reference]
        assert_equal "Medicaid", insurer[:display]
      end

      def test_to_fhir_maps_medicare_to_cms
        request = CoverageEligibilityRequest.new(patient_dfn: "123", coverage_type: "medicare_a")
        insurer = request.to_fhir[:insurer]

        assert_equal "Organization/CMS", insurer[:reference]
      end

      def test_to_fhir_includes_item_with_category_coding
        request = CoverageEligibilityRequest.new(patient_dfn: "123", coverage_type: "medicaid")
        items = request.to_fhir[:item]

        assert_equal 1, items.length
        coding = items.first[:category][:coding].first
        assert_equal "medicaid", coding[:code]
      end

      def test_to_fhir_includes_provider_reference_when_set
        request = CoverageEligibilityRequest.new(
          patient_dfn: "123", coverage_type: "medicaid", provider_ien: "456"
        )
        provider = request.to_fhir[:provider]

        assert_equal "Practitioner/456", provider[:reference]
      end

      def test_to_fhir_omits_provider_when_not_set
        request = CoverageEligibilityRequest.new(patient_dfn: "123", coverage_type: "medicaid")
        fhir = request.to_fhir

        refute fhir.key?(:provider)
      end

      # -- from_fhir --

      def test_from_fhir_reconstructs_basic_fields
        fhir_hash = {
          id: "cer-001",
          patient: { reference: "Patient/123" },
          servicedDate: "2026-04-08",
          purpose: ["benefits"],
          item: [{ category: { coding: [{ code: "medicaid" }] } }]
        }

        request = CoverageEligibilityRequest.from_fhir(fhir_hash)

        assert_equal "cer-001", request.id
        assert_equal "123", request.patient_dfn
        assert_equal "medicaid", request.coverage_type
        assert_equal Date.new(2026, 4, 8), request.service_date
        assert_equal "benefits", request.purpose
      end

      def test_from_fhir_handles_string_keys
        fhir_hash = {
          "id" => "cer-002",
          "patient" => { "reference" => "Patient/456" },
          "servicedDate" => "2026-04-08",
          "item" => [{ "category" => { "coding" => [{ "code" => "medicare_a" }] } }]
        }

        request = CoverageEligibilityRequest.from_fhir(fhir_hash)

        assert_equal "cer-002", request.id
        assert_equal "456", request.patient_dfn
        assert_equal "medicare_a", request.coverage_type
      end

      def test_from_fhir_defaults_purpose_when_missing
        fhir_hash = {
          patient: { reference: "Patient/123" },
          servicedDate: "2026-04-08",
          item: [{ category: { coding: [{ code: "medicaid" }] } }]
        }

        request = CoverageEligibilityRequest.from_fhir(fhir_hash)
        assert_equal "benefits", request.purpose
      end
    end
  end
end
