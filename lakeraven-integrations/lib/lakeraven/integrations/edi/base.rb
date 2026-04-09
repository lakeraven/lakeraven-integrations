# frozen_string_literal: true

require "lakeraven/fhir"

module Lakeraven
  module Integrations
    module Edi
      # Abstract EDI interface for Lakeraven integrations.
      #
      # Handles eligibility checks (270/271), claims submission (837),
      # claim status inquiries (276/277), and remittance processing (835).
      #
      # Built-in implementations:
      #   Lakeraven::Integrations::Edi::Mock — canned responses for dev/test
      #   (see lakeraven-directx12 gem) Lakeraven::DirectX12::Adapter —
      #     raw X12 over HTTPS/SFTP/AS2, the public vendor-lock hedge
      #
      # Private concrete implementations (commercial clearinghouses, etc.) live
      # in the private lakeraven-private monorepo as per-vendor gems. Each
      # implements this interface.
      #
      # Engines (corvid, lakeraven-ehr) depend only on this interface. SaaS
      # shells wire a concrete adapter instance into the interface slot at boot.
      #
      # --- FHIR-native interface ---
      #
      # check_eligibility takes and returns Lakeraven::Fhir::* decorators
      # around FHIR R4 resources. Concrete adapters translate between the
      # FHIR resources and their vendor-specific format internally. Engines
      # (corvid, lakeraven-ehr) speak only FHIR; they never see X12 segments
      # or vendor JSON shapes.
      #
      # submit_claim, check_claim_status, and process_remittance are still
      # hash-shaped (X12-flavored) — they will migrate to FHIR Claim,
      # ClaimResponse, and ExplanationOfBenefit decorators once those
      # resource types are added to lakeraven-fhir-models.
      #
      # --- Money representation ---
      #
      # All money fields on hash-shaped responses are integer cents. No
      # BigDecimal, no Float. Avoids precision issues and matches how most
      # payment systems represent amounts on the wire.
      class Base
        # Check patient eligibility with a payer (270/271).
        #
        # @param request [Lakeraven::Fhir::CoverageEligibilityRequest]
        #   FHIR CoverageEligibilityRequest decorator carrying the standard
        #   FHIR fields (patient.reference, insurer.reference, item.category,
        #   servicedDate) plus Lakeraven extensions needed for adapter payload
        #   construction (payer_id, subscriber_id, subscriber_first_name,
        #   subscriber_last_name, subscriber_dob, provider_npi, service_type).
        # @return [Lakeraven::Fhir::CoverageEligibilityResponse]
        #   FHIR CoverageEligibilityResponse decorator with enrolled/
        #   not_enrolled/pending/denied/exhausted/error status and, when
        #   applicable, coverage period and plan details.
        def check_eligibility(request)
          raise NotImplementedError, "#{self.class}#check_eligibility not implemented"
        end

        # Submit a claim to a payer (837 professional or institutional).
        #
        # @param request [Hash] claim request with keys:
        #   :claim_type              (String, required) "837P" or "837I"
        #   :payer_id                (String, required)
        #   :subscriber_id           (String, required)
        #   :patient_first_name      (String, required)
        #   :patient_last_name       (String, required)
        #   :patient_dob             (String "YYYY-MM-DD", required)
        #   :provider_npi            (String, required)
        #   :provider_tax_id         (String, required for 837P)
        #   :facility_npi            (String, optional; used by 837I)
        #   :service_date            (String "YYYY-MM-DD", required)
        #   :diagnosis_codes         (Array<String>, required)
        #   :procedure_codes         (Array<Hash>, required for 837P)
        #                             each: {code, modifier, units, charge_cents}
        #   :revenue_codes           (Array<Hash>, required for 837I)
        #                             each: {code, description, charge_cents}
        #   :place_of_service        (String, optional; default "11")
        #   :total_charge_cents      (Integer, optional)
        # @return [ClaimResponse]
        def submit_claim(request)
          raise NotImplementedError, "#{self.class}#submit_claim not implemented"
        end

        # Check status of a previously-submitted claim (276/277).
        #
        # @param claim_reference [String] the claim_id returned in a prior
        #   ClaimResponse. Exact format is adapter-specific (clearinghouse
        #   claim ID, tracking number, payer claim number, etc.).
        # @return [StatusResponse]
        def check_claim_status(claim_reference)
          raise NotImplementedError, "#{self.class}#check_claim_status not implemented"
        end

        # Process a remittance (835). A remittance file typically contains
        # many claim payments; this method returns one RemittanceResponse per
        # claim payment.
        #
        # @param remittance_reference_or_data [String, Hash]
        #   - String: remittance identifier to fetch from a backend service
        #     (for adapters that pull remittances from a clearinghouse API)
        #   - Hash: pre-parsed remittance payload (for adapters that receive
        #     remittances via push or parse raw 835 files locally)
        # @return [Array<RemittanceResponse>] one entry per claim payment;
        #   adapters that process only a single claim payment return a
        #   single-element array
        def process_remittance(remittance_reference_or_data)
          raise NotImplementedError, "#{self.class}#process_remittance not implemented"
        end
      end

      # -----------------------------------------------------------------
      # Response value objects
      #
      # Eligibility uses the FHIR-native Lakeraven::Fhir decorators from
      # lakeraven-fhir-models. The claim / status / remittance responses
      # below remain hash-shaped Data classes with integer-cent money
      # until Claim / ClaimResponse / ExplanationOfBenefit decorators are
      # added to lakeraven-fhir-models.
      # -----------------------------------------------------------------

      ClaimResponse = Data.define(
        :accepted,        # Boolean
        :claim_id,        # String — payer- or clearinghouse-assigned claim number
        :tracking_number, # String — clearinghouse tracking reference
        :errors,          # Array of error hashes
        :raw_response     # Hash — full 999/277CA or adapter-specific payload
      ) do
        def success?
          accepted == true
        end
      end

      StatusResponse = Data.define(
        :claim_id,                 # String
        :status_code,              # String — X12 status category code
        :status_description,       # String
        :effective_date,           # Date or nil
        :total_charge_cents,       # Integer or nil
        :paid_amount_cents,        # Integer or nil
        :raw_response              # Hash — full 277 or adapter-specific payload
      )

      RemittanceResponse = Data.define(
        :claim_id,                     # String
        :paid_amount_cents,            # Integer
        :patient_responsibility_cents, # Integer
        :adjustments,                  # Array<Hash> — each has :reason_code,
                                       #   :amount_cents, :description
        :service_lines,                # Array<Hash> — each has :procedure_code,
                                       #   :charged_cents, :paid_cents
        :raw_response                  # Hash — full 835 or adapter payload
      )
    end
  end
end
