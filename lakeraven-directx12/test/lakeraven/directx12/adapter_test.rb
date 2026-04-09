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
          assert_respond_to @adapter, method, "Adapter should implement #{method}"
        end
      end

      def test_initializes_with_endpoint
        assert_equal "https://edi.example.com/submit", @adapter.endpoint
      end

      # -- X12 envelope generation --

      def test_build_x12_270_has_correct_se_segment_count
        request = eligibility_request
        envelope = @adapter.send(:build_x12_270, request)
        assert_envelope_has_consistent_se_count(envelope)
      end

      def test_build_x12_837_has_correct_se_segment_count
        envelope = @adapter.send(:build_x12_837, claim_request("837P"))
        assert_envelope_has_consistent_se_count(envelope)
      end

      def test_build_x12_276_has_correct_se_segment_count
        envelope = @adapter.send(:build_x12_276, "CLM-001")
        assert_envelope_has_consistent_se_count(envelope)
      end

      def test_build_x12_270_includes_isa_and_iea_envelope
        envelope = @adapter.send(:build_x12_270, eligibility_request)
        assert envelope.start_with?("ISA*"), "Should start with ISA segment"
        assert_includes envelope, "IEA*"
        assert_includes envelope, "GS*HS*"
        assert_includes envelope, "GE*1*"
      end

      def test_build_x12_270_includes_patient_and_provider_data
        envelope = @adapter.send(:build_x12_270,
          payer_id: "BCBS",
          subscriber_id: "PAT-1",
          subscriber_first_name: "Alice",
          subscriber_last_name: "Anderson",
          subscriber_dob: "1970-01-01",
          provider_npi: "9876543210",
          service_type: "30"
        )
        assert_includes envelope, "NM1*IL*1******MI*PAT-1~"
        assert_includes envelope, "NM1*1P*2*****XX*9876543210~"
        assert_includes envelope, "EQ*30~"
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

      def test_extract_x12_value_matches_segment_type_with_qualifier
        raw = "NM1*PR*2*ACME HEALTH~NM1*IL*1*DOE*JOHN~"
        assert_equal "DOE", @adapter.send(:extract_x12_value, raw, "NM1*IL", 3)
      end

      def test_extract_x12_value_returns_nil_for_unmatched_qualifier
        raw = "NM1*PR*2*ACME~"
        assert_nil @adapter.send(:extract_x12_value, raw, "NM1*IL", 3)
      end

      def test_extract_x12_value_returns_nil_for_nil_input
        assert_nil @adapter.send(:extract_x12_value, nil, "NM1", 1)
      end

      # -- Response parser return types --

      def test_parse_271_response_returns_eligibility_response
        result = @adapter.send(:parse_271_response, "NM1*PR*2*ACME~")
        assert_instance_of Lakeraven::Integrations::Edi::EligibilityResponse, result
      end

      def test_parse_claim_response_returns_claim_response
        result = @adapter.send(:parse_claim_response, "CLM*C001~")
        assert_instance_of Lakeraven::Integrations::Edi::ClaimResponse, result
      end

      def test_parse_277_response_returns_status_response
        result = @adapter.send(:parse_277_response, "REF*BLT*CLM-001~STC*A1**Received~")
        assert_instance_of Lakeraven::Integrations::Edi::StatusResponse, result
      end

      def test_parse_835_returns_array_of_remittance_responses
        results = @adapter.send(:parse_835, claim_id: "CLM-001", paid_amount_cents: 10_000)
        assert_kind_of Array, results
        assert_equal 1, results.length
        assert_instance_of Lakeraven::Integrations::Edi::RemittanceResponse, results.first
        assert_equal "CLM-001", results.first.claim_id
        assert_equal 10_000, results.first.paid_amount_cents
      end

      def test_parse_835_uses_integer_cents
        results = @adapter.send(:parse_835,
          claim_id: "CLM-001",
          paid_amount_cents: 12_345,
          patient_responsibility_cents: 2_500
        )
        assert_kind_of Integer, results.first.paid_amount_cents
        assert_kind_of Integer, results.first.patient_responsibility_cents
        assert_equal 12_345, results.first.paid_amount_cents
        assert_equal 2_500, results.first.patient_responsibility_cents
      end

      # -- Transport errors --

      def test_unknown_transport_raises_argument_error
        adapter = Adapter.new(
          endpoint: "https://edi.example.com/submit",
          sender_id: "SENDER123",
          receiver_id: "RECEIVER456",
          transport: :unknown
        )
        assert_raises(ArgumentError) { adapter.send(:submit_transaction, "ST*270*~") }
      end

      def test_sftp_transport_raises_not_implemented
        adapter = Adapter.new(
          endpoint: "sftp://edi.example.com",
          sender_id: "SENDER123",
          receiver_id: "RECEIVER456",
          transport: :sftp
        )
        assert_raises(NotImplementedError) { adapter.send(:submit_transaction, "ST*270*~") }
      end

      private

      def assert_envelope_has_consistent_se_count(envelope)
        segments = envelope.split("\n")
        st_index = segments.index { |s| s.start_with?("ST*") }
        se_index = segments.index { |s| s.start_with?("SE*") }
        refute_nil st_index, "Envelope should include ST segment"
        refute_nil se_index, "Envelope should include SE segment"

        se_segment = segments[se_index]
        declared_count = se_segment.split("*")[1].to_i
        actual_count = se_index - st_index + 1
        assert_equal actual_count, declared_count,
          "SE01 should equal ST-through-SE segment count"
      end

      def eligibility_request
        {
          payer_id: "BCBS",
          subscriber_id: "PAT-1",
          subscriber_first_name: "Alice",
          subscriber_last_name: "Anderson",
          subscriber_dob: "1970-01-01",
          provider_npi: "1234567890",
          service_type: "30"
        }
      end

      def claim_request(claim_type)
        {
          claim_type: claim_type,
          payer_id: "BCBS",
          subscriber_id: "SUB-1",
          patient_first_name: "Alice",
          patient_last_name: "Anderson",
          patient_dob: "1970-01-01",
          provider_npi: "1234567890",
          provider_tax_id: "123456789",
          service_date: "2026-04-08",
          diagnosis_codes: ["J06.9"],
          procedure_codes: [{ code: "99213", modifier: nil, units: 1, charge_cents: 15_000 }]
        }
      end
    end
  end
end
