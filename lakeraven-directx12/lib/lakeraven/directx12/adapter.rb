# frozen_string_literal: true

require "net/http"
require "json"
require "date"

require "lakeraven/integrations/edi/base"

module Lakeraven
  module DirectX12
    # Generic X12 EDI adapter for direct clearinghouse communication.
    #
    # Generates raw X12 transactions and submits via configurable transport
    # (SFTP, AS2, or HTTPS). Works with any clearinghouse that accepts
    # standard X12 270/837/276 transactions.
    #
    # This is the public vendor-lock hedge: any Lakeraven customer can
    # self-host the public stack (corvid + lakeraven-integrations +
    # lakeraven-directx12) and bring their own clearinghouse contract,
    # with no dependency on any private commercial adapter gem.
    #
    # For vendor-specific clearinghouse integrations, see private gems
    # in the lakeraven-private monorepo (e.g., lakeraven-stedi).
    class Adapter < Lakeraven::Integrations::Edi::Base
      attr_reader :endpoint

      def initialize(endpoint:, sender_id:, receiver_id:, transport: :https, credentials: {})
        @endpoint = endpoint
        @sender_id = sender_id
        @receiver_id = receiver_id
        @transport = transport
        @credentials = credentials
      end

      def check_eligibility(patient_id, provider_npi, service_type_codes)
        envelope = build_x12_270(patient_id, provider_npi, service_type_codes)
        response = submit_transaction(envelope)
        parse_271_response(response)
      end

      def submit_claim(claim_params)
        envelope = build_x12_837(claim_params)
        response = submit_transaction(envelope)
        parse_claim_response(response)
      end

      def check_claim_status(claim_id)
        envelope = build_x12_276(claim_id)
        response = submit_transaction(envelope)
        parse_277_response(response)
      end

      def process_remittance(remittance_data)
        parse_835(remittance_data)
      end

      private

      # -----------------------------------------------------------------
      # X12 envelope builders
      # -----------------------------------------------------------------

      def build_x12_270(patient_id, provider_npi, service_type_codes)
        control_number = generate_control_number
        service_codes = Array(service_type_codes).join("^")

        transaction_segments = [
          "ST*270*#{control_number}~",
          "BHT*0022*13*#{control_number}*#{date_stamp}*#{time_stamp}~",
          "HL*1**20*1~",
          "NM1*PR*2*#{@receiver_id}*****PI*#{@receiver_id}~",
          "HL*2*1*21*1~",
          "NM1*1P*2*****XX*#{provider_npi}~",
          "HL*3*2*22*0~",
          "NM1*IL*1******MI*#{patient_id}~",
          "EQ*#{service_codes}~"
        ]

        wrap_envelope("HS", "005010X279A1", control_number, transaction_segments)
      end

      def build_x12_837(claim_params)
        control_number = generate_control_number

        transaction_segments = [
          "ST*837*#{control_number}~",
          "BHT*0019*00*#{control_number}*#{date_stamp}*#{time_stamp}*CH~"
        ]

        wrap_envelope("HC", "005010X222A1", control_number, transaction_segments)
      end

      def build_x12_276(claim_id)
        control_number = generate_control_number

        transaction_segments = [
          "ST*276*#{control_number}~",
          "BHT*0010*13*#{control_number}*#{date_stamp}*#{time_stamp}~",
          "REF*BLT*#{claim_id}~"
        ]

        wrap_envelope("HR", "005010X212", control_number, transaction_segments)
      end

      # -----------------------------------------------------------------
      # Response parsers (stubs — real parsing requires X12 segment parser)
      # Production X12 parsing and validation (segment counts, control
      # numbers, loops) should use a proper X12 parser library. The
      # envelope builders above use placeholder SE segment counts that
      # won't pass trading partner validation.
      # -----------------------------------------------------------------

      def parse_271_response(raw)
        Lakeraven::Integrations::Edi::EligibilityResponse.new(
          eligible: !raw.nil?,
          payer_name: extract_x12_value(raw, "NM1", 3) || "Unknown",
          subscriber_id: extract_x12_value(raw, "NM1*IL", 9),
          group_number: nil,
          coverage_start: nil,
          coverage_end: nil,
          service_types: [],
          raw_response: { raw: raw }
        )
      end

      def parse_claim_response(raw)
        Lakeraven::Integrations::Edi::ClaimResponse.new(
          accepted: !raw.nil?,
          claim_id: extract_x12_value(raw, "CLM", 1) || "UNKNOWN",
          tracking_number: extract_x12_value(raw, "REF*TJ", 2),
          errors: [],
          raw_response: { raw: raw }
        )
      end

      def parse_277_response(raw)
        Lakeraven::Integrations::Edi::StatusResponse.new(
          claim_id: extract_x12_value(raw, "REF*BLT", 2) || "UNKNOWN",
          status_code: extract_x12_value(raw, "STC", 1),
          status_description: extract_x12_value(raw, "STC", 4) || "",
          effective_date: nil,
          total_charge: nil,
          paid_amount: nil,
          raw_response: { raw: raw }
        )
      end

      def parse_835(remittance_data)
        Lakeraven::Integrations::Edi::RemittanceResponse.new(
          claim_id: remittance_data[:claim_id] || "UNKNOWN",
          paid_amount: BigDecimal(remittance_data[:paid_amount]&.to_s || "0"),
          patient_responsibility: BigDecimal(remittance_data[:patient_responsibility]&.to_s || "0"),
          adjustments: remittance_data[:adjustments] || [],
          service_lines: remittance_data[:service_lines] || [],
          raw_response: remittance_data
        )
      end

      # -----------------------------------------------------------------
      # Transport
      # -----------------------------------------------------------------

      def submit_transaction(envelope)
        case @transport
        when :https
          submit_https(envelope)
        when :sftp, :as2
          raise NotImplementedError, "#{@transport} transport not yet implemented"
        else
          raise ArgumentError, "Unknown transport: #{@transport}"
        end
      end

      def submit_https(envelope)
        uri = URI.parse(@endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 60

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/edi-x12"
        request.body = envelope

        if @credentials[:username]
          request.basic_auth(@credentials[:username], @credentials[:password])
        elsif @credentials[:bearer_token]
          request["Authorization"] = "Bearer #{@credentials[:bearer_token]}"
        end

        response = http.request(request)
        response.is_a?(Net::HTTPSuccess) ? response.body : nil
      end

      # -----------------------------------------------------------------
      # Helpers
      # -----------------------------------------------------------------

      def isa_segment(control_number)
        "ISA*00*          *00*          *ZZ*#{@sender_id.ljust(15)}*ZZ*#{@receiver_id.ljust(15)}*#{date_stamp_short}*#{time_stamp}*^*00501*#{control_number.rjust(9, '0')}*0*P*:~"
      end

      def isa_trailer(control_number)
        "IEA*1*#{control_number.rjust(9, '0')}~"
      end

      # Wraps transaction segments in ISA/GS/SE/GE/IEA envelope.
      # SE01 is computed dynamically (ST + body + SE = count).
      def wrap_envelope(functional_id, version, control_number, transaction_segments)
        se_count = transaction_segments.size + 1 # +1 for SE itself

        segments = [
          isa_segment(control_number),
          "GS*#{functional_id}*#{@sender_id}*#{@receiver_id}*#{date_stamp}*#{time_stamp}*#{control_number}*X*#{version}~",
          *transaction_segments,
          "SE*#{se_count}*#{control_number}~",
          "GE*1*#{control_number}~",
          isa_trailer(control_number)
        ]

        segments.join("\n")
      end

      # ISA13/IEA02 control numbers must be exactly 9 digits.
      def generate_control_number
        Time.now.strftime("%H%M%S") + format("%03d", rand(1000))
      end

      def date_stamp
        Date.today.strftime("%Y%m%d")
      end

      def date_stamp_short
        Date.today.strftime("%y%m%d")
      end

      def time_stamp
        Time.now.strftime("%H%M")
      end

      # Extract a value from an X12 response by segment type and optional qualifier.
      # segment_id can be "NM1" (match segment type only) or "NM1*IL" (match
      # segment type + qualifier in element 1).
      def extract_x12_value(raw, segment_id, position = 1)
        return nil unless raw.is_a?(String)

        seg_type, qualifier = segment_id.split("*", 2)

        raw.split("~").each do |seg|
          elements = seg.strip.split("*")
          next unless elements[0] == seg_type
          next if qualifier && elements[1] != qualifier

          return elements[position]
        end
        nil
      end
    end
  end
end
