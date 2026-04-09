# frozen_string_literal: true

require_relative "integrations/version"
require_relative "integrations/edi/base"
require_relative "integrations/edi/mock"

# Note: the old Data-class-based response types (EligibilityResponse,
# ClaimResponse, StatusResponse, RemittanceResponse) have been replaced
# by FHIR-native Lakeraven::Fhir::* decorators from lakeraven-fhir-models.

module Lakeraven
  # Lakeraven::Integrations is the interface-contract layer between Lakeraven
  # engines (corvid, lakeraven-ehr) and concrete backend implementations.
  #
  # Engines depend only on this gem and its interface modules. Concrete adapters
  # (wrapping RPMS, FHIR, commercial clearinghouses, OSS projects, etc.) live in
  # sibling gems in the lakeraven-integrations monorepo (for public concretes)
  # or in the private lakeraven-private monorepo (for private concretes).
  #
  # SaaS shells (corvid-saas, lakeraven-ehr-saas) are the composition layer —
  # they bundle engines + concrete adapter gems and wire the adapters into the
  # interface slots at boot time via Lakeraven::Integrations.configure.
  module Integrations
    class Configuration
      attr_accessor :edi_adapter

      def initialize
        @edi_adapter = nil
      end
    end

    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      def reset_configuration!
        @configuration = Configuration.new
      end

      def edi_adapter
        configuration.edi_adapter
      end
    end
  end
end
