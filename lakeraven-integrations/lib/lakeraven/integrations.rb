# frozen_string_literal: true

require_relative "integrations/version"
require_relative "integrations/edi/base"
require_relative "integrations/edi/mock"
require_relative "integrations/clinical/patient_lookup/base"
require_relative "integrations/clinical/patient_lookup/mock"
require_relative "integrations/clinical/clinical_data_reader/base"
require_relative "integrations/clinical/clinical_data_reader/mock"
require_relative "integrations/supplemental/attributes"
require_relative "integrations/supplemental/payer_category"
require_relative "integrations/supplemental/source_descriptor"
require_relative "integrations/supplemental/data_reader/base"
require_relative "integrations/supplemental/data_reader/mock"

# Note: the old Data-class-based response types (EligibilityResponse,
# ClaimResponse, StatusResponse, RemittanceResponse) have been replaced
# by FHIR-native Lakeraven::Fhir::* decorators from lakeraven-fhir-edi.

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
      attr_accessor :edi_adapter, :patient_lookup_adapter, :clinical_data_adapter

      # Supplemental::DataReader implementations. An Array (unlike the
      # singular adapter slots) because a deployment can read supplemental
      # data from several EHR platforms at once; each reader carries its own
      # SourceDescriptor.
      attr_reader :supplemental_data_readers

      def initialize
        @edi_adapter = nil
        @patient_lookup_adapter = nil
        @clinical_data_adapter = nil
        @supplemental_data_readers = [].freeze
      end

      # Registers supplemental readers, rejecting duplicate SourceDescriptor
      # ids — source ids must be unique per deployment for provenance to be
      # meaningful — and rejecting readers whose descriptor channel is not
      # +supplemental+: a primary_fhir descriptor in this slot would stamp
      # supplemental records with primary-feed lineage. Stores a frozen copy
      # so the registered set can only change through another assignment
      # inside +configure+.
      def supplemental_data_readers=(readers)
        readers = Array(readers)
        duplicate_ids = readers.map { |r| r.source_descriptor.id }.tally.select { |_, count| count > 1 }.keys
        unless duplicate_ids.empty?
          raise ArgumentError, "duplicate supplemental source ids: #{duplicate_ids.join(', ')}"
        end

        non_supplemental = readers.map(&:source_descriptor).reject(&:supplemental?)
        unless non_supplemental.empty?
          raise ArgumentError,
                "supplemental_data_readers require supplemental-channel descriptors; got " +
                non_supplemental.map { |d| "#{d.id} (#{d.channel})" }.join(", ")
        end

        @supplemental_data_readers = readers.dup.freeze
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

      def patient_lookup_adapter
        configuration.patient_lookup_adapter
      end

      def clinical_data_adapter
        configuration.clinical_data_adapter
      end

      # @return [Array<Supplemental::DataReader::Base>] the registered
      #   readers, as a frozen copy — global config cannot be mutated
      #   outside +configure+.
      def supplemental_data_readers
        configuration.supplemental_data_readers.dup.freeze
      end
    end
  end
end
