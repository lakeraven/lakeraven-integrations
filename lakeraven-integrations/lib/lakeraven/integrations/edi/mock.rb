# frozen_string_literal: true

require "date"
require "securerandom"

require_relative "base"

module Lakeraven
  module Integrations
    module Edi
      # Canned EDI responses for dev/test.
      # Returns successful 271/837/277/835 equivalents in integer cents.
      class Mock < Base
        def check_eligibility(request)
          EligibilityResponse.new(
            eligible: true,
            payer_name: "Mock Medicaid",
            subscriber_id: "MOCK-#{request[:subscriber_id] || '1'}",
            group_number: nil,
            coverage_start: Date.new(Date.today.year, 1, 1),
            coverage_end: Date.new(Date.today.year, 12, 31),
            service_types: [request[:service_type] || "30"],
            raw_response: { mock: true, transaction: "271" }
          )
        end

        def submit_claim(request)
          claim_id = request[:claim_id] || "CLM-#{SecureRandom.hex(4).upcase}"

          ClaimResponse.new(
            accepted: true,
            claim_id: claim_id,
            tracking_number: "TRK-#{SecureRandom.hex(4).upcase}",
            errors: [],
            raw_response: { mock: true, transaction: "999" }
          )
        end

        def check_claim_status(claim_reference)
          StatusResponse.new(
            claim_id: claim_reference,
            status_code: "A1",
            status_description: "Acknowledged/Receipt - The claim/encounter has been received.",
            effective_date: Date.today,
            total_charge_cents: 150_000, # $1500.00
            paid_amount_cents: 120_000, # $1200.00
            raw_response: { mock: true, transaction: "277" }
          )
        end

        def process_remittance(remittance_reference_or_data)
          claim_id = if remittance_reference_or_data.is_a?(Hash)
            remittance_reference_or_data[:claim_id] || "CLM-MOCK"
          else
            "CLM-#{remittance_reference_or_data}"
          end

          [
            RemittanceResponse.new(
              claim_id: claim_id,
              paid_amount_cents: 120_000, # $1200.00
              patient_responsibility_cents: 30_000, # $300.00
              adjustments: [
                {
                  reason_code: "CO-45",
                  amount_cents: 30_000, # $300.00
                  description: "Charges exceed fee schedule"
                }
              ],
              service_lines: [
                {
                  procedure_code: "99213",
                  charged_cents: 15_000, # $150.00
                  paid_cents: 12_000 # $120.00
                },
                {
                  procedure_code: "99214",
                  charged_cents: 25_000, # $250.00
                  paid_cents: 20_000 # $200.00
                }
              ],
              raw_response: { mock: true, transaction: "835" }
            )
          ]
        end
      end
    end
  end
end
