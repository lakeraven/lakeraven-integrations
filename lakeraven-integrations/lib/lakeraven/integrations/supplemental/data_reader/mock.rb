# frozen_string_literal: true

require "date"
require "securerandom"

require_relative "base"

module Lakeraven
  module Integrations
    module Supplemental
      module DataReader
        # In-memory mock supplemental adapter for testing without an EHR
        # backend. Also serves as the executable spec of the normalized
        # shape: seeding builds the same Attributes-coded FHIR::Observation
        # a concrete adapter must emit.
        class Mock < Base
          attr_reader :source_descriptor

          def initialize(source_descriptor: default_descriptor)
            @source_descriptor = source_descriptor
            @patient_observations = {}
            @visit_observations = {}
          end

          # Seed a patient-level attribute value.
          # @param patient_id [String]
          # @param attribute [String] one of Attributes::PATIENT_LEVEL
          # @param value [Numeric, TrueClass, FalseClass, String] per the attribute's value kind
          # @param effective [Date, nil] effective date (nil = undated, matches any period)
          # @return [FHIR::Observation] the normalized observation
          def seed_patient_attribute(patient_id, attribute, value, effective: nil)
            validate_attribute!(attribute, Attributes::PATIENT_LEVEL)
            observation = build_observation(patient_id, attribute, value, effective, nil)
            (@patient_observations[patient_id.to_s] ||= []) << observation
            observation
          end

          # Seed a visit-level attribute value.
          # @param patient_id [String]
          # @param encounter_id [String] visit the attribute classifies
          # @param attribute [String] one of Attributes::VISIT_LEVEL
          # @param value [String] per the attribute's value kind
          # @param effective [Date, nil] visit date (nil = undated, matches any period)
          # @return [FHIR::Observation] the normalized observation
          def seed_visit_attribute(patient_id, encounter_id, attribute, value, effective: nil)
            validate_attribute!(attribute, Attributes::VISIT_LEVEL)
            observation = build_observation(patient_id, attribute, value, effective, encounter_id)
            (@visit_observations[patient_id.to_s] ||= []) << observation
            observation
          end

          def patient_attributes(patient_ids, period: nil)
            read(@patient_observations, patient_ids, period)
          end

          def visit_attributes(patient_ids, period: nil)
            read(@visit_observations, patient_ids, period)
          end

          private

          def default_descriptor
            SourceDescriptor.new(id: "mock", ehr_platform: "rpms", channel: "supplemental")
          end

          def validate_attribute!(attribute, allowed)
            return if allowed.include?(attribute)

            raise ArgumentError, "attribute must be one of: #{allowed.join(', ')} (got #{attribute.inspect})"
          end

          def build_observation(patient_id, attribute, value, effective, encounter_id)
            FHIR::Observation.new(
              id: SecureRandom.uuid,
              status: "final",
              code: { coding: [{ system: Attributes::CODE_SYSTEM, code: attribute }] },
              subject: { reference: "Patient/#{patient_id}" },
              encounter: encounter_id ? { reference: "Encounter/#{encounter_id}" } : nil,
              effectiveDateTime: effective&.to_s,
              **value_element(Attributes::DEFINITIONS.fetch(attribute)[:value], value)
            )
          end

          def value_element(kind, value)
            case kind
            when :percent then { valueQuantity: { value: value, unit: "%" } }
            when :boolean then { valueBoolean: value }
            else { valueString: value.to_s }
            end
          end

          def read(store, patient_ids, period)
            matches = Array(patient_ids).flat_map { |id| store[id.to_s] || [] }
            matches = matches.select { |observation| in_period?(observation, period) } if period
            tag_source(matches)
          end

          def in_period?(observation, period)
            date = parse_date(observation.effectiveDateTime)
            date.nil? || period.cover?(date)
          end

          def parse_date(value)
            return nil if value.nil? || value.to_s.empty?

            Date.parse(value.to_s)
          rescue ArgumentError
            nil
          end
        end
      end
    end
  end
end
