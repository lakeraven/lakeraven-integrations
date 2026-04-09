# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module DirectX12
    class AdapterTest < Minitest::Test
      def setup
        @adapter = Adapter.new(
          endpoint: "https://edi.example.com/submit",
          sender_id: "SENDER123",
          receiver_id: "RECEIVER456"
        )
      end

      # -- Inheritance / interface conformance --

      def test_inherits_from_edi_base
        assert_kind_of Lakeraven::Integrations::Edi::Base, @adapter
      end

      def test_implements_all_base_interface_methods
        base_methods = Lakeraven::Integrations::Edi::Base.instance_methods(false)
        base_methods.each do |method|
          assert_respond_to @adapter, method
        end
      end

      def test_initializes_with_endpoint
        assert_equal "https://edi.example.com/submit", @adapter.endpoint
      end

      # -- FHIR-native check_eligibility --

      def test_build_x12_270_accepts_fhir_request
        request = eligibility_request
        envelope = @adapter.send(:build_x12_270, request)
        assert envelope.start_with?("ISA*")
        assert_includes envelope, "NM1*IL*1******MI*PAT-1~"
        assert_includes envelope, "NM1*1P*2*****XX*1234567890~"
      end

      def test_parse_271_response_returns_fhir_coverage_eligibility_response
        result = @adapter.send(:parse_271_response, "NM1*PR*2*ACME~", eligibility_request)
        assert_instance_of Lakeraven::Fhir::CoverageEligibilityResponse, result
      end

      # -- X12 envelope --

      def test_build_x12_270_has_correct_se_segment_count
        assert_envelope_has_consistent_se_count(@adapter.send(:build_x12_270, eligibility_request))
      end

      def test_build_x12_837_has_correct_se_segment_count
        assert_envelope_has_consistent_se_count(@adapter.send(:build_x12_837, claim_request))
      end

      def test_build_x12_276_has_correct_se_segment_count
        assert_envelope_has_consistent_se_count(@adapter.send(:build_x12_276, "CLM-001"))
      end

      def test_build_x12_270_includes_full_envelope
        envelope = @adapter.send(:build_x12_270, eligibility_request)
        assert envelope.start_with?("ISA*")
        assert_includes envelope, "IEA*"
        assert_includes envelope, "GS*HS*"
        assert_includes envelope, "GE*1*"
      end

      # -- FHIR-native submit_claim --

      def test_build_x12_837_accepts_fhir_claim
        envelope = @adapter.send(:build_x12_837, claim_request)
        assert_includes envelope, "ST*837*"
      end

      def test_parse_claim_response_returns_fhir_claim_response
        result = @adapter.send(:parse_claim_response, "CLM*C001~", claim_request)
        assert_instance_of Lakeraven::Fhir::ClaimResponse, result
        assert result.accepted?
      end

      # -- FHIR-native check_claim_status --

      def test_parse_277_response_returns_fhir_claim_response
        result = @adapter.send(:parse_277_response, "REF*BLT*CLM-001~STC*A1**Received~", "CLM-001")
        assert_instance_of Lakeraven::Fhir::ClaimResponse, result
      end

      # -- FHIR-native process_remittance --

      def test_parse_835_returns_array_of_explanation_of_benefit
        results = @adapter.send(:parse_835, {
          claim_id: "CLM-001",
          paid_amount_cents: 10_000,
          patient_responsibility_cents: 2_000,
          patient_dfn: "123"
        })
        assert_kind_of Array, results
        assert_equal 1, results.length
        assert_instance_of Lakeraven::Fhir::ExplanationOfBenefit, results.first
        assert_equal "CLM-001", results.first.claim_id
        assert_equal 10_000, results.first.paid_amount_cents
      end

      # -- Control number --

      def test_generate_control_number_is_nine_digits
        control = @adapter.send(:generate_control_number)
        assert_equal 9, control.length
        assert_match(/\A\d{9}\z/, control)
      end

      # -- X12 response parser --

      def test_extract_x12_value_matches_segment_type_only
        raw = "NM1*PR*2*ACME HEALTH~NM1*IL*1*DOE*JOHN~"
        assert_equal "ACME HEALTH", @adapter.send(:extract_x12_value, raw, "NM1", 3)
      end

      def test_extract_x12_value_matches_with_qualifier
        raw = "NM1*PR*2*ACME HEALTH~NM1*IL*1*DOE*JOHN~"
        assert_equal "DOE", @adapter.send(:extract_x12_value, raw, "NM1*IL", 3)
      end

      def test_extract_x12_value_returns_nil_for_unmatched
        assert_nil @adapter.send(:extract_x12_value, "NM1*PR*2*ACME~", "NM1*IL", 3)
      end

      def test_extract_x12_value_returns_nil_for_nil_input
        assert_nil @adapter.send(:extract_x12_value, nil, "NM1", 1)
      end

      # -- Transport errors --

      def test_unknown_transport_raises_argument_error
        adapter = Adapter.new(endpoint: "x", sender_id: "S", receiver_id: "R", transport: :unknown)
        assert_raises(ArgumentError) { adapter.send(:submit_transaction, "x") }
      end

      def test_sftp_transport_raises_not_implemented
        adapter = Adapter.new(endpoint: "x", sender_id: "S", receiver_id: "R", transport: :sftp)
        assert_raises(NotImplementedError) { adapter.send(:submit_transaction, "x") }
      end

      private

      def assert_envelope_has_consistent_se_count(envelope)
        segments = envelope.split("\n")
        st_index = segments.index { |s| s.start_with?("ST*") }
        se_index = segments.index { |s| s.start_with?("SE*") }
        refute_nil st_index
        refute_nil se_index
        declared_count = segments[se_index].split("*")[1].to_i
        actual_count = se_index - st_index + 1
        assert_equal actual_count, declared_count
      end

      def eligibility_request
        Lakeraven::Fhir::CoverageEligibilityRequest.new(
          patient_dfn: "PAT-1", coverage_type: "medicaid",
          payer_id: "BCBS", subscriber_id: "PAT-1",
          provider_npi: "1234567890", service_type: "30"
        )
      end

      def claim_request
        Lakeraven::Fhir::Claim.new(
          claim_type: "837P", patient_dfn: "PAT-1",
          payer_id: "BCBS", subscriber_id: "SUB-1",
          provider_npi: "1234567890", provider_tax_id: "123456789",
          service_date: "2026-04-08", diagnosis_codes: ["J06.9"],
          procedure_codes: [{ code: "99213", units: 1, charge_cents: 15_000 }],
          total_charge_cents: 15_000
        )
      end
    end
  end
end
