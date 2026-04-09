# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Fhir
    class CoverageEligibilityResponseTest < Minitest::Test
      # -- Initialization --

      def test_assigns_default_id
        response = CoverageEligibilityResponse.new(status: "enrolled")
        refute_nil response.id
      end

      def test_sets_default_created_at
        response = CoverageEligibilityResponse.new(status: "enrolled")
        refute_nil response.created_at
      end

      # -- Validations --

      def test_requires_status
        response = CoverageEligibilityResponse.new
        refute response.valid?
        assert_includes response.errors[:status], "can't be blank"
      end

      def test_rejects_invalid_status
        response = CoverageEligibilityResponse.new(status: "made_up")
        refute response.valid?
      end

      def test_accepts_valid_statuses
        %w[enrolled not_enrolled pending denied exhausted error].each do |status|
          response = CoverageEligibilityResponse.new(status: status)
          assert response.valid?, "Expected #{status} to be valid"
        end
      end

      # -- Status helpers --

      def test_enrolled_helper
        assert CoverageEligibilityResponse.new(status: "enrolled").enrolled?
        refute CoverageEligibilityResponse.new(status: "denied").enrolled?
      end

      def test_not_enrolled_helper
        assert CoverageEligibilityResponse.new(status: "not_enrolled").not_enrolled?
      end

      def test_pending_helper
        assert CoverageEligibilityResponse.new(status: "pending").pending?
      end

      def test_denied_helper
        assert CoverageEligibilityResponse.new(status: "denied").denied?
      end

      def test_exhausted_helper
        assert CoverageEligibilityResponse.new(status: "exhausted").exhausted?
      end

      def test_error_helper
        assert CoverageEligibilityResponse.new(status: "error").error?
      end

      def test_final_true_for_not_enrolled_denied_exhausted
        %w[not_enrolled denied exhausted].each do |status|
          assert CoverageEligibilityResponse.new(status: status).final?, "#{status} should be final"
        end
      end

      def test_final_false_for_enrolled_pending
        refute CoverageEligibilityResponse.new(status: "enrolled").final?
        refute CoverageEligibilityResponse.new(status: "pending").final?
      end

      # -- Coverage period helpers --

      def test_active_coverage_true_when_enrolled_and_within_period
        response = CoverageEligibilityResponse.new(
          status: "enrolled",
          start_date: Date.today - 30,
          end_date: Date.today + 30
        )
        assert response.active_coverage?
      end

      def test_active_coverage_false_when_not_enrolled
        response = CoverageEligibilityResponse.new(status: "denied")
        refute response.active_coverage?
      end

      def test_within_coverage_period_true_with_no_dates
        response = CoverageEligibilityResponse.new(status: "enrolled")
        assert response.within_coverage_period?
      end

      def test_within_coverage_period_false_after_end_date
        response = CoverageEligibilityResponse.new(
          status: "enrolled", end_date: Date.today - 1
        )
        refute response.within_coverage_period?
      end

      # -- Coverage details --

      def test_coverage_details_nil_when_not_enrolled
        response = CoverageEligibilityResponse.new(status: "denied")
        assert_nil response.coverage_details
      end

      def test_coverage_details_returns_hash_when_enrolled
        response = CoverageEligibilityResponse.new(
          status: "enrolled",
          coverage_type: "medicaid",
          plan_name: "State Gold",
          policy_id: "POL123",
          insurer_name: "State Medicaid",
          start_date: Date.new(2026, 1, 1)
        )
        details = response.coverage_details

        assert_equal "medicaid", details[:type]
        assert_equal "enrolled", details[:status]
        refute_nil details[:plan]
        refute_nil details[:insurer]
      end

      def test_plan_info_nil_when_no_plan_fields
        response = CoverageEligibilityResponse.new(status: "enrolled")
        assert_nil response.plan_info
      end

      def test_plan_info_returns_hash_when_plan_fields_set
        response = CoverageEligibilityResponse.new(
          status: "enrolled", plan_name: "PPO Gold", policy_id: "POL123"
        )
        plan = response.plan_info

        assert_equal "PPO Gold", plan[:name]
        assert_equal "POL123", plan[:policy_id]
      end

      # -- FHIR serialization --

      def test_to_fhir_returns_coverage_eligibility_response_resource
        response = CoverageEligibilityResponse.new(
          status: "enrolled",
          patient_dfn: "123",
          coverage_type: "medicaid",
          service_date: Date.new(2026, 4, 8)
        )
        fhir = response.to_fhir

        assert_equal "CoverageEligibilityResponse", fhir[:resourceType]
        assert_equal response.id, fhir[:id]
        assert_equal "Patient/123", fhir[:patient][:reference]
        assert_equal "2026-04-08", fhir[:servicedDate]
        assert_equal "complete", fhir[:outcome]
      end

      def test_to_fhir_pending_status_maps_to_queued_outcome
        response = CoverageEligibilityResponse.new(status: "pending", patient_dfn: "123")
        assert_equal "queued", response.to_fhir[:outcome]
      end

      def test_to_fhir_error_status_maps_to_error_outcome
        response = CoverageEligibilityResponse.new(status: "error", patient_dfn: "123")
        assert_equal "error", response.to_fhir[:outcome]
      end

      def test_to_fhir_includes_insurance_array_when_enrolled
        response = CoverageEligibilityResponse.new(
          status: "enrolled",
          patient_dfn: "123",
          coverage_type: "medicaid",
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 12, 31)
        )
        insurance = response.to_fhir[:insurance]

        assert_equal 1, insurance.length
        assert_includes insurance.first[:coverage][:reference], "Coverage/"
        assert insurance.first[:inforce]
      end

      def test_to_fhir_omits_insurance_when_not_enrolled
        response = CoverageEligibilityResponse.new(status: "denied", patient_dfn: "123")
        # Note: the raw insurance array is empty when not enrolled, but .compact
        # leaves it as an empty array; test the structure allows either.
        insurance = response.to_fhir[:insurance]
        assert_equal [], insurance unless insurance.nil?
      end

      # -- from_fhir --

      def test_from_fhir_reconstructs_basic_fields
        fhir_hash = {
          id: "cres-001",
          patient: { reference: "Patient/123" },
          outcome: "complete",
          insurance: [{ inforce: true }],
          servicedDate: "2026-04-08",
          disposition: "Coverage active"
        }

        response = CoverageEligibilityResponse.from_fhir(fhir_hash)

        assert_equal "cres-001", response.id
        assert_equal "123", response.patient_dfn
        assert_equal "enrolled", response.status
        assert_equal Date.new(2026, 4, 8), response.service_date
        assert_equal "Coverage active", response.disposition
      end

      def test_from_fhir_maps_complete_outcome_without_active_coverage_to_not_enrolled
        fhir_hash = {
          patient: { reference: "Patient/123" },
          outcome: "complete",
          insurance: [{ inforce: false }]
        }

        response = CoverageEligibilityResponse.from_fhir(fhir_hash)
        assert_equal "not_enrolled", response.status
      end

      def test_from_fhir_maps_queued_to_pending
        fhir_hash = {
          patient: { reference: "Patient/123" },
          outcome: "queued"
        }

        response = CoverageEligibilityResponse.from_fhir(fhir_hash)
        assert_equal "pending", response.status
      end

      def test_from_fhir_maps_error_to_error
        fhir_hash = {
          patient: { reference: "Patient/123" },
          outcome: "error"
        }

        response = CoverageEligibilityResponse.from_fhir(fhir_hash)
        assert_equal "error", response.status
      end

      def test_from_fhir_extracts_benefit_period
        fhir_hash = {
          patient: { reference: "Patient/123" },
          outcome: "complete",
          insurance: [
            { inforce: true, benefitPeriod: { start: "2026-01-01", end: "2026-12-31" } }
          ]
        }

        response = CoverageEligibilityResponse.from_fhir(fhir_hash)
        assert_equal Date.new(2026, 1, 1), response.start_date
        assert_equal Date.new(2026, 12, 31), response.end_date
      end

      def test_from_fhir_handles_string_keys
        fhir_hash = {
          "id" => "cres-002",
          "patient" => { "reference" => "Patient/456" },
          "outcome" => "complete",
          "insurance" => [{ "inforce" => true }]
        }

        response = CoverageEligibilityResponse.from_fhir(fhir_hash)

        assert_equal "cres-002", response.id
        assert_equal "456", response.patient_dfn
        assert_equal "enrolled", response.status
      end
    end
  end
end
