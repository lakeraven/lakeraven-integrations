# frozen_string_literal: true

require "lakeraven/fhir"

module Lakeraven
  module Integrations
    module Edi
      # Abstract EDI interface for Lakeraven integrations.
      #
      # All four methods take and return Lakeraven::Fhir::* decorators wrapping
      # FHIR R4 resources from fhir_models. Concrete adapters translate between
      # the FHIR resources and their vendor-specific format internally. Engines
      # (corvid, lakeraven-ehr) speak only FHIR.
      #
      # Money is integer cents inside the Lakeraven decorator layer, but
      # serializes to FHIR Money (decimal dollars) on the wire.
      class Base
        # @param request [Lakeraven::Fhir::CoverageEligibilityRequest]
        # @return [Lakeraven::Fhir::CoverageEligibilityResponse]
        def check_eligibility(request)
          raise NotImplementedError, "#{self.class}#check_eligibility not implemented"
        end

        # @param request [Lakeraven::Fhir::Claim]
        # @return [Lakeraven::Fhir::ClaimResponse]
        def submit_claim(request)
          raise NotImplementedError, "#{self.class}#submit_claim not implemented"
        end

        # @param claim_reference [String]
        # @return [Lakeraven::Fhir::ClaimResponse]
        def check_claim_status(claim_reference)
          raise NotImplementedError, "#{self.class}#check_claim_status not implemented"
        end

        # @param remittance_reference_or_data [String, Hash]
        # @return [Array<Lakeraven::Fhir::ExplanationOfBenefit>]
        def process_remittance(remittance_reference_or_data)
          raise NotImplementedError, "#{self.class}#process_remittance not implemented"
        end
      end
    end
  end
end
