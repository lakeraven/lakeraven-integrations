# frozen_string_literal: true

require "bigdecimal"
require "date"
require "securerandom"

require_relative "base"

module Lakeraven
  module Integrations
    module Edi
      # Canned EDI responses for dev/test.
      # Returns successful 271/837/277/835 equivalents.
      class Mock < Base
        def check_eligibility(patient_id, provider_npi, service_type_codes)
          EligibilityResponse.new(
            eligible: true,
            payer_name: "Mock Medicaid",
            subscriber_id: "MOCK-#{patient_id}",
            group_number: nil,
            coverage_start: Date.new(Date.today.year, 1, 1),
            coverage_end: Date.new(Date.today.year, 12, 31),
            service_types: Array(service_type_codes),
            raw_response: { mock: true, transaction: "271" }
          )
        end

        def submit_claim(claim_params)
          claim_id = claim_params[:claim_id] || "CLM-#{SecureRandom.hex(4).upcase}"

          ClaimResponse.new(
            accepted: true,
            claim_id: claim_id,
            tracking_number: "TRK-#{SecureRandom.hex(4).upcase}",
            errors: [],
            raw_response: { mock: true, transaction: "999" }
          )
        end

        def check_claim_status(claim_id)
          StatusResponse.new(
            claim_id: claim_id,
            status_code: "A1",
            status_description: "Acknowledged/Receipt - The claim/encounter has been received.",
            effective_date: Date.today,
            total_charge: BigDecimal("1500.00"),
            paid_amount: BigDecimal("1200.00"),
            raw_response: { mock: true, transaction: "277" }
          )
        end

        def process_remittance(remittance_data)
          claim_id = remittance_data[:claim_id] || "CLM-MOCK"

          RemittanceResponse.new(
            claim_id: claim_id,
            paid_amount: BigDecimal("1200.00"),
            patient_responsibility: BigDecimal("300.00"),
            adjustments: [
              { reason_code: "CO-45", amount: BigDecimal("300.00"), description: "Charges exceed fee schedule" }
            ],
            service_lines: [
              { procedure_code: "99213", charged: BigDecimal("150.00"), paid: BigDecimal("120.00") },
              { procedure_code: "99214", charged: BigDecimal("250.00"), paid: BigDecimal("200.00") }
            ],
            raw_response: { mock: true, transaction: "835" }
          )
        end
      end
    end
  end
end
