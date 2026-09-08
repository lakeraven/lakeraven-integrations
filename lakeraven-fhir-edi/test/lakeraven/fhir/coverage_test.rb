# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Fhir
    class CoverageTest < Minitest::Test
      # -- Initialization --

      def test_assigns_default_id_when_not_provided
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid")
        refute_nil coverage.id
        assert_match(/\A[0-9a-f-]{36}\z/, coverage.id)
      end

      def test_preserves_explicit_id
        coverage = Coverage.new(id: "explicit-id", patient_dfn: "123", coverage_type: "medicaid")
        assert_equal "explicit-id", coverage.id
      end

      def test_sets_created_at_default
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid")
        refute_nil coverage.created_at
      end

      def test_defaults_status_to_active
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid")
        assert_equal "active", coverage.status
      end

      def test_defaults_relationship_to_self
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid")
        assert_equal "self", coverage.relationship
      end

      def test_sets_default_payor_name_from_coverage_type
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid")
        assert_equal "Medicaid", coverage.payor_name
      end

      def test_preserves_explicit_payor_name
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid", payor_name: "State Medicaid")
        assert_equal "State Medicaid", coverage.payor_name
      end

      # -- Validations --

      def test_requires_patient_dfn
        coverage = Coverage.new(coverage_type: "medicaid")
        refute coverage.valid?
        assert_includes coverage.errors[:patient_dfn], "can't be blank"
      end

      def test_requires_coverage_type
        coverage = Coverage.new(patient_dfn: "123")
        refute coverage.valid?
        assert_includes coverage.errors[:coverage_type], "can't be blank"
      end

      def test_rejects_invalid_coverage_type
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "made_up")
        refute coverage.valid?
        assert_includes coverage.errors[:coverage_type], "is not a valid coverage type"
      end

      def test_accepts_valid_coverage_types
        %w[medicare_a medicare_b medicare_d medicaid private_insurance
           va_benefits workers_comp auto_insurance state_program tribal_program].each do |type|
          coverage = Coverage.new(patient_dfn: "123", coverage_type: type)
          assert coverage.valid?, "Expected #{type} to be valid"
        end
      end

      def test_rejects_invalid_status
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid", status: "made_up")
        refute coverage.valid?
      end

      def test_accepts_valid_statuses
        %w[active cancelled draft entered-in-error exhausted not_enrolled denied pending].each do |status|
          coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid", status: status)
          assert coverage.valid?, "Expected status #{status} to be valid"
        end
      end

      # -- Status helpers --

      def test_active_returns_true_for_active_within_period
        coverage = Coverage.new(
          patient_dfn: "123", coverage_type: "medicaid",
          start_date: Date.today - 30, end_date: Date.today + 30
        )
        assert coverage.active?
      end

      def test_active_returns_false_when_cancelled
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid", status: "cancelled")
        refute coverage.active?
      end

      def test_expired_returns_true_when_end_date_passed
        coverage = Coverage.new(
          patient_dfn: "123", coverage_type: "medicaid",
          end_date: Date.today - 1
        )
        assert coverage.expired?
      end

      def test_expired_returns_false_when_no_end_date
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid")
        refute coverage.expired?
      end

      def test_cancelled_returns_true_for_cancelled_status
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid", status: "cancelled")
        assert coverage.cancelled?
      end

      def test_within_coverage_period_true_with_no_dates
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid")
        assert coverage.within_coverage_period?
      end

      def test_within_coverage_period_false_before_start_date
        coverage = Coverage.new(
          patient_dfn: "123", coverage_type: "medicaid",
          start_date: Date.today + 1
        )
        refute coverage.within_coverage_period?
      end

      # -- Payor helpers --

      def test_medicare_true_for_medicare_a
        assert Coverage.new(patient_dfn: "123", coverage_type: "medicare_a").medicare?
      end

      def test_medicare_true_for_medicare_b
        assert Coverage.new(patient_dfn: "123", coverage_type: "medicare_b").medicare?
      end

      def test_medicare_false_for_medicaid
        refute Coverage.new(patient_dfn: "123", coverage_type: "medicaid").medicare?
      end

      def test_medicaid_true_for_medicaid
        assert Coverage.new(patient_dfn: "123", coverage_type: "medicaid").medicaid?
      end

      def test_private_insurance_true_for_private
        assert Coverage.new(patient_dfn: "123", coverage_type: "private_insurance").private_insurance?
      end

      def test_va_benefits_true_for_va
        assert Coverage.new(patient_dfn: "123", coverage_type: "va_benefits").va_benefits?
      end

      def test_government_payer_true_for_medicaid_medicare_va
        %w[medicare_a medicare_b medicare_d medicaid va_benefits].each do |type|
          assert Coverage.new(patient_dfn: "123", coverage_type: type).government_payer?, "#{type} should be government"
        end
      end

      def test_government_payer_false_for_private
        refute Coverage.new(patient_dfn: "123", coverage_type: "private_insurance").government_payer?
      end

      # -- Coordination of benefits --

      def test_default_coordination_order_for_private_is_primary
        assert_equal 1, Coverage.new(patient_dfn: "123", coverage_type: "private_insurance").coordination_order
      end

      def test_default_coordination_order_for_medicaid_is_three
        assert_equal 3, Coverage.new(patient_dfn: "123", coverage_type: "medicaid").coordination_order
      end

      def test_explicit_order_overrides_default
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid", order: 1)
        assert_equal 1, coverage.coordination_order
      end

      def test_primary_true_when_order_is_one
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "private_insurance")
        assert coverage.primary?
      end

      def test_secondary_true_when_order_is_two
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicare_a")
        assert coverage.secondary?
      end

      # -- FHIR serialization --

      def test_to_fhir_returns_coverage_resource
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid", plan_name: "State Medicaid Gold")
        fhir = coverage.to_fhir

        assert_equal "Coverage", fhir[:resourceType]
        assert_equal coverage.id, fhir[:id]
        assert_equal "active", fhir[:status]
        assert_equal "Patient/123", fhir[:beneficiary][:reference]
      end

      def test_to_fhir_includes_coverage_type_coding
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid")
        coding = coverage.to_fhir[:type][:coding].first

        assert_equal "http://terminology.hl7.org/CodeSystem/v3-ActCode", coding[:system]
        assert_equal "MEDICAID", coding[:code]
      end

      def test_to_fhir_maps_medicare_to_cms
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicare_a")
        payor = coverage.to_fhir[:payor].first

        assert_equal "Organization/CMS", payor[:reference]
      end

      def test_to_fhir_maps_medicaid_to_state_medicaid
        coverage = Coverage.new(patient_dfn: "123", coverage_type: "medicaid")
        payor = coverage.to_fhir[:payor].first

        assert_equal "Organization/StateMedicaid", payor[:reference]
      end

      def test_to_fhir_period_includes_start_and_end
        coverage = Coverage.new(
          patient_dfn: "123", coverage_type: "medicaid",
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 12, 31)
        )
        period = coverage.to_fhir[:period]

        assert_equal "2026-01-01", period[:start]
        assert_equal "2026-12-31", period[:end]
      end

      # -- from_fhir round-trip --

      def test_from_fhir_reconstructs_basic_fields
        fhir_hash = {
          id: "cov-001",
          status: "active",
          type: { coding: [{ code: "MEDICAID" }] },
          beneficiary: { reference: "Patient/123" },
          payor: [{ display: "State Medicaid" }]
        }

        coverage = Coverage.from_fhir(fhir_hash)

        assert_equal "cov-001", coverage.id
        assert_equal "123", coverage.patient_dfn
        assert_equal "medicaid", coverage.coverage_type
        assert_equal "active", coverage.status
      end

      def test_from_fhir_handles_string_keys
        fhir_hash = {
          "id" => "cov-002",
          "status" => "active",
          "type" => { "coding" => [{ "code" => "HIP" }] },
          "beneficiary" => { "reference" => "Patient/456" }
        }

        coverage = Coverage.from_fhir(fhir_hash)

        assert_equal "cov-002", coverage.id
        assert_equal "456", coverage.patient_dfn
        assert_equal "private_insurance", coverage.coverage_type
      end

      def test_from_fhir_extracts_period
        fhir_hash = {
          type: { coding: [{ code: "MEDICAID" }] },
          beneficiary: { reference: "Patient/123" },
          period: { start: "2026-01-01", end: "2026-12-31" }
        }

        coverage = Coverage.from_fhir(fhir_hash)

        assert_equal Date.new(2026, 1, 1), coverage.start_date
        assert_equal Date.new(2026, 12, 31), coverage.end_date
      end
    end
  end
end
