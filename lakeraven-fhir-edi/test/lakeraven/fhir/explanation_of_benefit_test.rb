# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Fhir
    class ExplanationOfBenefitTest < Minitest::Test
      def test_basic_construction
        eob = ExplanationOfBenefit.new(
          claim_id: "CLM-001",
          patient_dfn: "123",
          paid_amount_cents: 120_000,
          patient_responsibility_cents: 30_000,
          adjustments: [
            { reason_code: "CO-45", amount_cents: 30_000, description: "Contractual" }
          ],
          service_lines: [
            { procedure_code: "99213", charged_cents: 15_000, paid_cents: 12_000 }
          ]
        )

        assert_equal "CLM-001", eob.claim_id
        assert_equal "123", eob.patient_dfn
        assert_equal 120_000, eob.paid_amount_cents
        assert_equal 30_000, eob.patient_responsibility_cents
        assert_equal 1, eob.adjustments.length
        assert_equal 1, eob.service_lines.length
      end

      def test_wraps_fhir_explanation_of_benefit_resource
        eob = ExplanationOfBenefit.new(claim_id: "CLM-001", patient_dfn: "123")
        assert_instance_of ::FHIR::ExplanationOfBenefit, eob.__getobj__
      end

      def test_to_fhir_returns_eob_hash
        eob = ExplanationOfBenefit.new(claim_id: "CLM-001", patient_dfn: "123")
        fhir = eob.to_fhir
        assert_equal "ExplanationOfBenefit", fhir[:resourceType]
      end

      def test_to_json_produces_valid_fhir_json
        eob = ExplanationOfBenefit.new(claim_id: "CLM-001", patient_dfn: "123")
        parsed = JSON.parse(eob.to_json)
        assert_equal "ExplanationOfBenefit", parsed["resourceType"]
      end

      def test_defaults_id
        eob = ExplanationOfBenefit.new(claim_id: "CLM-001", patient_dfn: "123")
        refute_nil eob.id
      end

      def test_defaults_paid_and_responsibility_to_zero
        eob = ExplanationOfBenefit.new(claim_id: "CLM-001", patient_dfn: "123")
        assert_equal 0, eob.paid_amount_cents
        assert_equal 0, eob.patient_responsibility_cents
      end

      def test_defaults_adjustments_and_service_lines_to_empty
        eob = ExplanationOfBenefit.new(claim_id: "CLM-001", patient_dfn: "123")
        assert_equal [], eob.adjustments
        assert_equal [], eob.service_lines
      end
    end
  end
end
