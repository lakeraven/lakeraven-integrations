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

        # Produce a remittance advice (835 / EOB) for a claim.
        #
        # When called with a *claim payload* — a Hash carrying billing intent
        # (a procedure_code and/or amount fields) — the money is validated and
        # the remittance is derived from it. Invalid or inverted amounts fail
        # closed (raise ArgumentError): a mock must never silently emit a canned
        # payment in place of a real adjudication.
        #
        # The canned remittance is reserved for the legacy lookup path: a bare
        # string/reference or a Hash that carries no billing data.
        def process_remittance(remittance_reference_or_data)
          if claim_payload?(remittance_reference_or_data)
            [remittance_for_claim(remittance_reference_or_data)]
          else
            [canned_remittance(remittance_reference_or_data)]
          end
        end

        private

        # A claim payload is a Hash that carries billing intent. A Hash with
        # only a claim_id (or a bare string reference) is a legacy lookup.
        def claim_payload?(input)
          input.is_a?(Hash) &&
            (input.key?(:procedure_code) ||
             input.key?(:billed_amount_cents) ||
             input.key?(:allowed_amount_cents))
        end

        def remittance_for_claim(data)
          billed = validate_cents!(data[:billed_amount_cents], "billed_amount_cents")
          allowed = validate_cents!(data[:allowed_amount_cents], "allowed_amount_cents")

          # A real Medicare-Like Rate is never above the billed charge.
          if allowed > billed
            raise ArgumentError,
              "allowed_amount_cents (#{allowed}) cannot exceed billed_amount_cents (#{billed})"
          end

          # Pay the allowed (Medicare-Like Rate) amount; the difference is a
          # single CO-45 contractual adjustment; and — since PRC is the payer
          # of last resort — there is no patient responsibility.
          paid = [allowed, billed].min
          adjustment = [billed - allowed, 0].max
          Lakeraven::Fhir::ExplanationOfBenefit.new(
            claim_id: data[:claim_id] || "CLM-MOCK",
            patient_dfn: data[:patient_dfn] || "mock",
            paid_amount_cents: paid,
            patient_responsibility_cents: 0,
            adjustments: [
              { reason_code: "CO-45", amount_cents: adjustment, description: "Charges exceed the Medicare-Like Rate fee schedule" }
            ],
            service_lines: [
              { procedure_code: data[:procedure_code] || "UNSPECIFIED", charged_cents: billed, paid_cents: paid }
            ]
          )
        end

        # Backward-compatible canned remittance for the legacy lookup path.
        def canned_remittance(reference)
          claim_id =
            if reference.is_a?(Hash)
              reference[:claim_id] || "CLM-MOCK"
            else
              "CLM-#{reference}"
            end

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
        end

        # Amounts must be present, integer cents, and non-negative. Anything
        # else (nil, "N/A", a float, a negative) fails closed.
        def validate_cents!(value, field)
          unless value.is_a?(Integer) && value >= 0
            raise ArgumentError,
              "#{field} must be a non-negative integer number of cents, got #{value.inspect}"
          end
          value
        end
      end
    end
  end
end
