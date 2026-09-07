# frozen_string_literal: true

require "fhir_models"

require_relative "../attributes"
require_relative "../payer_category"
require_relative "../source_descriptor"

module Lakeraven
  module Integrations
    module Supplemental
      module DataReader
        # Abstract per-EHR-platform adapter interface for UDS supplemental
        # data: patient/visit-level attributes that the platform's FHIR API
        # does not expose, living in its registration/eligibility/billing
        # internals (income as % FPL, sliding-fee class, housing status,
        # agricultural-worker status, veteran status, language barrier, visit
        # service category) — plus payer-category coverage records.
        #
        # Concrete adapters reach into each platform's non-FHIR access path
        # internally — this interface stays transport-agnostic; consumers see
        # only FHIR. Attribute reads return FHIR::Observation resources
        # normalized to the Attributes vocabulary (one internal code system,
        # so downstream SQL-on-FHIR sees a single vocabulary regardless of
        # source EHR); #patient_coverages returns FHIR::Coverage resources
        # typed from the PayerCategory vocabulary. Everything returned is
        # tagged with source provenance (+meta.source+ from
        # #source_descriptor — see #tag_source).
        #
        # == Patient IDs
        #
        # Every read accepts +patient_ids+ as a single String or an
        # Array<String>.
        #
        # == Period semantics
        #
        # +period:+ is a Range<Date> with an *inclusive* end. For
        # patient-level, registration-derived data (patient attributes and
        # coverages) it means "current as of period end": implementations
        # return the latest value effective on or before the period's end
        # date — at most one value per attribute per patient per read.
        # Undated values are currently-effective and always match. For
        # visit-level attributes the period selects visits occurring within
        # the period (inclusive of both endpoints). +period: nil+ returns
        # everything current (patient-level) / all visits (visit-level).
        #
        # == Batching and failure
        #
        # Callers with large cohorts should batch +patient_ids+ themselves;
        # implementations define (and document) their own batch limits and
        # may reject oversized requests. Partial-failure contract: a read
        # either returns complete results for every requested patient or
        # raises — implementations must never silently skip patients they
        # failed to read.
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
          # @param patient_ids [String, Array<String>] patient ID(s) (cohort or single)
          # @param period [Range<Date>, nil] current as of period end (inclusive); nil = current
          # @param attributes [Array<String>, nil] subset of Attributes::PATIENT_LEVEL
          #   codes to read; nil = all
          # @return [Array<FHIR::Observation>] coded from Attributes::CODE_SYSTEM
          def patient_attributes(patient_ids, period: nil, attributes: nil)
            raise NotImplementedError, "#{self.class}#patient_attributes not implemented"
          end

          # Visit-level UDS supplemental attributes (Attributes::VISIT_LEVEL),
          # each carrying an +encounter+ reference.
          # @param patient_ids [String, Array<String>] patient ID(s) (cohort or single)
          # @param period [Range<Date>, nil] visits within the period (inclusive); nil = all
          # @param attributes [Array<String>, nil] subset of Attributes::VISIT_LEVEL
          #   codes to read; nil = all
          # @return [Array<FHIR::Observation>] coded from Attributes::CODE_SYSTEM
          def visit_attributes(patient_ids, period: nil, attributes: nil)
            raise NotImplementedError, "#{self.class}#visit_attributes not implemented"
          end

          # Payer-category coverage from eligibility/billing internals,
          # normalized as FHIR::Coverage with +type.coding+ from
          # PayerCategory::CODE_SYSTEM (medicaid, medicare, private,
          # uninsured, other-public) and +beneficiary+ referencing the
          # patient.
          # @param patient_ids [String, Array<String>] patient ID(s) (cohort or single)
          # @param period [Range<Date>, nil] current as of period end (inclusive); nil = current
          # @return [Array<FHIR::Coverage>] provenance-tagged coverage resources
          def patient_coverages(patient_ids, period: nil)
            raise NotImplementedError, "#{self.class}#patient_coverages not implemented"
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
