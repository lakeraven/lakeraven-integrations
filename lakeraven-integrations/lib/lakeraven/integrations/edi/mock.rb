# frozen_string_literal: true

require "date"
require "securerandom"

require "lakeraven/fhir"
require_relative "base"

module Lakeraven
  module Integrations
    module Edi
      # Canned FHIR-native EDI responses for dev/test.
      class Mock < Base
        def check_eligibility(request)
          Lakeraven::Fhir::CoverageEligibilityResponse.new(
            patient_dfn: request.patient_dfn,
            coverage_type: request.coverage_type,
            status: "enrolled",
            service_date: request.service_date || Date.today,
            start_date: Date.new(Date.today.year, 1, 1),
            end_date: Date.new(Date.today.year, 12, 31),
            plan_name: "Mock Medicaid PPO",
            policy_id: "MOCK-POL-#{request.subscriber_id || '1'}",
            insurer_name: "Mock Medicaid"
          )
        end

        def submit_claim(request)
          Lakeraven::Fhir::ClaimResponse.new(
            accepted: true,
            claim_id: "CLM-#{SecureRandom.hex(4).upcase}",
            tracking_number: "TRK-#{SecureRandom.hex(4).upcase}",
            patient_dfn: request.patient_dfn
          )
        end

        def check_claim_status(claim_reference)
          Lakeraven::Fhir::ClaimResponse.new(
            accepted: true,
            claim_id: claim_reference,
            tracking_number: "TRK-#{SecureRandom.hex(4).upcase}",
            patient_dfn: "mock",
            paid_amount_cents: 120_000
          )
        end

        def process_remittance(remittance_reference_or_data)
          claim_id = if remittance_reference_or_data.is_a?(Hash)
            remittance_reference_or_data[:claim_id] || "CLM-MOCK"
          else
            "CLM-#{remittance_reference_or_data}"
          end

          [
            Lakeraven::Fhir::ExplanationOfBenefit.new(
              claim_id: claim_id,
              patient_dfn: "mock",
              paid_amount_cents: 120_000,
              patient_responsibility_cents: 30_000,
              adjustments: [
                { reason_code: "CO-45", amount_cents: 30_000, description: "Charges exceed fee schedule" }
              ],
              service_lines: [
                { procedure_code: "99213", charged_cents: 15_000, paid_cents: 12_000 },
                { procedure_code: "99214", charged_cents: 25_000, paid_cents: 20_000 }
              ]
            )
          ]
        end
      end
    end
  end
end
