# frozen_string_literal: true

require "fhir_models"

require_relative "../attributes"
require_relative "../source_descriptor"

module Lakeraven
  module Integrations
    module Supplemental
      module DataReader
        # Abstract per-EHR-platform adapter interface for UDS supplemental
        # data: patient/visit-level attributes that the platform's FHIR API
        # does not expose, living in its registration/eligibility/billing
        # internals (income as % FPL, sliding-fee class, payer category,
        # housing status, agricultural-worker status, veteran status, language
        # barrier, visit service category).
        #
        # Concrete adapters reach into each platform's non-FHIR access path
        # internally — this interface stays transport-agnostic; consumers see
        # only FHIR. All read methods return FHIR::Observation resources
        # normalized to the Attributes vocabulary (one internal code system,
        # so downstream SQL-on-FHIR sees a single vocabulary regardless of
        # source EHR) and tagged with source provenance (+meta.source+ from
        # #source_descriptor — see #tag_source).
        #
        # Read-only by design: supplemental data substantiates reporting, it
        # is never written back to the source EHR.
        class Base
          # Descriptor identifying this source for provenance and audit.
          # @return [SourceDescriptor]
          def source_descriptor
            raise NotImplementedError, "#{self.class}#source_descriptor not implemented"
          end

          # Patient-level UDS supplemental attributes (Attributes::PATIENT_LEVEL).
          # @param patient_ids [Array<String>] patient IDs (cohort or single)
          # @param period [Range<Date>, nil] restrict to this period; nil = all
          # @return [Array<FHIR::Observation>] coded from Attributes::CODE_SYSTEM
          def patient_attributes(patient_ids, period: nil)
            raise NotImplementedError, "#{self.class}#patient_attributes not implemented"
          end

          # Visit-level UDS supplemental attributes (Attributes::VISIT_LEVEL),
          # each carrying an +encounter+ reference.
          # @param patient_ids [Array<String>] patient IDs (cohort or single)
          # @param period [Range<Date>, nil] restrict to this period; nil = all
          # @return [Array<FHIR::Observation>] coded from Attributes::CODE_SYSTEM
          def visit_attributes(patient_ids, period: nil)
            raise NotImplementedError, "#{self.class}#visit_attributes not implemented"
          end

          private

          # Stamp source provenance onto returned resources so downstream
          # consumers keep source-level lineage on the resource itself.
          # Concrete adapters call this on every batch they return.
          #
          # @param resources [Array<FHIR::Model>]
          # @return [Array<FHIR::Model>] the same resources, tagged
          def tag_source(resources)
            resources.each do |resource|
              resource.meta ||= FHIR::Meta.new
              resource.meta.source = source_descriptor.uri
            end
          end
        end
      end
    end
  end
end
