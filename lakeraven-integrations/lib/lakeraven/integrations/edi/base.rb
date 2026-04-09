# frozen_string_literal: true

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
      # Private commercial implementations (e.g. Stedi, CHC, Availity) live in
      # the private lakeraven-private monorepo as per-vendor gems like
      # lakeraven-stedi, lakeraven-fredi, etc. Each implements this interface.
      #
      # Engines (corvid, lakeraven-ehr) depend only on this interface. SaaS
      # shells wire a concrete adapter instance into the interface slot at boot.
      class Base
        # Submit a 270 eligibility inquiry to a payer via X12.
        # This is the payer-facing financial eligibility check.
        #
        # For EHR-sourced enrollment data (what the clinical system knows),
        # see the engine-specific adapter interfaces (e.g., Corvid::Adapters::Base#verify_eligibility).
        #
        # Returns an EligibilityResponse.
        def check_eligibility(patient_id, provider_npi, service_type_codes)
          raise NotImplementedError, "#{self.class}#check_eligibility not implemented"
        end

        # Submit an 837 professional/institutional claim.
        # Returns a ClaimResponse.
        def submit_claim(claim_params)
          raise NotImplementedError, "#{self.class}#submit_claim not implemented"
        end

        # Submit a 276 claim status inquiry.
        # Returns a StatusResponse.
        def check_claim_status(claim_id)
          raise NotImplementedError, "#{self.class}#check_claim_status not implemented"
        end

        # Process an 835 remittance advice.
        # Returns a RemittanceResponse.
        def process_remittance(remittance_data)
          raise NotImplementedError, "#{self.class}#process_remittance not implemented"
        end
      end

      # -----------------------------------------------------------------
      # Response value objects
      # -----------------------------------------------------------------

      EligibilityResponse = Data.define(
        :eligible,        # Boolean
        :payer_name,      # String
        :subscriber_id,   # String
        :group_number,    # String or nil
        :coverage_start,  # Date or nil
        :coverage_end,    # Date or nil
        :service_types,   # Array of covered service type codes
        :raw_response     # Hash — full parsed 271
      ) do
        def covered?
          eligible == true
        end
      end

      ClaimResponse = Data.define(
        :accepted,        # Boolean
        :claim_id,        # String — payer-assigned claim number
        :tracking_number, # String — clearinghouse tracking
        :errors,          # Array of error hashes
        :raw_response     # Hash — full 999/277CA
      ) do
        def success?
          accepted == true
        end
      end

      StatusResponse = Data.define(
        :claim_id,        # String
        :status_code,     # String — X12 status category code
        :status_description, # String
        :effective_date,  # Date or nil
        :total_charge,    # BigDecimal or nil
        :paid_amount,     # BigDecimal or nil
        :raw_response     # Hash — full 277
      )

      RemittanceResponse = Data.define(
        :claim_id,        # String
        :paid_amount,     # BigDecimal
        :patient_responsibility, # BigDecimal
        :adjustments,     # Array of adjustment hashes
        :service_lines,   # Array of service line hashes
        :raw_response     # Hash — full 835
      )
    end
  end
end
