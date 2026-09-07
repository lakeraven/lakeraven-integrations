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
        # (and PayerCategory-typed FHIR::Coverage) a concrete adapter must
        # emit, and reads implement the Base period contract — patient-level
        # reads are "current as of period end" with latest-wins, visit-level
        # reads select visits within the period.
        #
        # Reads return copies of the stored resources, so callers mutating a
        # returned resource cannot corrupt the store.
        class Mock < Base
          attr_reader :source_descriptor

          def initialize(source_descriptor: default_descriptor)
            @source_descriptor = source_descriptor
            @patient_observations = {}
            @visit_observations = {}
            @coverages = {}
          end

          # Seed a patient-level attribute value.
          # @param patient_id [String]
          # @param attribute [String] one of Attributes::PATIENT_LEVEL
          # @param value [Numeric, String] per the attribute's value kind —
          #   a Numeric whole percent for :percent, an enumerated code
          #   (the attribute's +values:+) for :coded
          # @param effective [Date, nil] effective date (nil = undated, currently effective)
          # @return [FHIR::Observation] the normalized observation
          def seed_patient_attribute(patient_id, attribute, value, effective: nil)
            validate_attribute!(attribute, Attributes::PATIENT_LEVEL)
            validate_value!(attribute, value)
            observation = build_observation(patient_id, attribute, value, effective, nil)
            (@patient_observations[patient_id.to_s] ||= []) << observation
            observation
          end

          # Seed a visit-level attribute value.
          # @param patient_id [String]
          # @param encounter_id [String] visit the attribute classifies
          # @param attribute [String] one of Attributes::VISIT_LEVEL
          # @param value [String] enumerated code per the attribute's +values:+
          # @param effective [Date, nil] visit date (nil = undated, matches any period)
          # @return [FHIR::Observation] the normalized observation
          def seed_visit_attribute(patient_id, encounter_id, attribute, value, effective: nil)
            validate_attribute!(attribute, Attributes::VISIT_LEVEL)
            validate_value!(attribute, value)
            observation = build_observation(patient_id, attribute, value, effective, encounter_id)
            (@visit_observations[patient_id.to_s] ||= []) << observation
            observation
          end

          # Seed a payer-category coverage record.
          # @param patient_id [String]
          # @param payer_category [String] one of PayerCategory::ALL
          # @param effective [Date, nil] effective date (nil = undated, currently effective)
          # @return [FHIR::Coverage] the normalized coverage
          def seed_patient_coverage(patient_id, payer_category, effective: nil)
            unless PayerCategory::ALL.include?(payer_category)
              raise ArgumentError,
                    "payer_category must be one of: #{PayerCategory::ALL.join(', ')} (got #{payer_category.inspect})"
            end

            coverage = FHIR::Coverage.new(
              id: SecureRandom.uuid,
              status: "active",
              type: { coding: [{ system: PayerCategory::CODE_SYSTEM, code: payer_category }] },
              beneficiary: { reference: "Patient/#{patient_id}" },
              period: effective ? { start: effective.to_s } : nil
            )
            (@coverages[patient_id.to_s] ||= []) << coverage
            coverage
          end

          def patient_attributes(patient_ids, period: nil, attributes: nil)
            attributes = validate_attribute_filter!(attributes, Attributes::PATIENT_LEVEL)
            observations = gather(@patient_observations, patient_ids)
            observations = observations.select { |o| attributes.include?(attribute_code(o)) }
            emit(latest_per(observations, period) { |o| [o.subject.reference, attribute_code(o)] })
          end

          def visit_attributes(patient_ids, period: nil, attributes: nil)
            attributes = validate_attribute_filter!(attributes, Attributes::VISIT_LEVEL)
            observations = gather(@visit_observations, patient_ids)
            observations = observations.select { |o| attributes.include?(attribute_code(o)) }
            observations = observations.select { |o| within_period?(o, period) } if period
            emit(observations)
          end

          def patient_coverages(patient_ids, period: nil)
            coverages = gather(@coverages, patient_ids)
            emit(latest_per(coverages, period) { |c| c.beneficiary.reference })
          end

          private

          def default_descriptor
            SourceDescriptor.new(id: "mock", ehr_platform: "rpms", channel: "supplemental")
          end

          def validate_attribute!(attribute, allowed)
            return if allowed.include?(attribute)

            raise ArgumentError, "attribute must be one of: #{allowed.join(', ')} (got #{attribute.inspect})"
          end

          def validate_value!(attribute, value)
            definition = Attributes::DEFINITIONS.fetch(attribute)
            case definition[:value]
            when :percent
              raise ArgumentError, "#{attribute} value must be Numeric (got #{value.inspect})" unless value.is_a?(Numeric)
            when :coded
              unless definition[:values].include?(value)
                raise ArgumentError,
                      "#{attribute} value must be one of: #{definition[:values].join(', ')} (got #{value.inspect})"
              end
            end
          end

          # @param attributes [Array<String>, nil] requested subset; nil = all
          # @return [Array<String>] the validated filter
          def validate_attribute_filter!(attributes, allowed)
            return allowed if attributes.nil?

            unknown = Array(attributes) - allowed
            unless unknown.empty?
              raise ArgumentError, "unknown attributes for this level: #{unknown.join(', ')} " \
                                   "(allowed: #{allowed.join(', ')})"
            end
            Array(attributes)
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
            when :percent
              { valueQuantity: { value: value, unit: "%", system: "http://unitsofmeasure.org", code: "%" } }
            else
              { valueCodeableConcept: { coding: [{ system: Attributes::VALUE_SYSTEM, code: value }] } }
            end
          end

          def attribute_code(observation)
            observation.code.coding.first.code
          end

          def gather(store, patient_ids)
            Array(patient_ids).flat_map { |id| store[id.to_s] || [] }
          end

          # Patient-level period contract: current as of period end (inclusive),
          # latest-wins — at most one resource per group key. Undated resources
          # are currently effective: they always match, but a dated candidate
          # wins over an undated one.
          def latest_per(resources, period, &group_key)
            candidates = resources
            candidates = candidates.select { |r| effective_date(r).nil? || effective_date(r) <= period.end } if period
            candidates
              .group_by(&group_key)
              .values
              .map { |group| group.max_by.with_index { |r, i| [effective_date(r) || EARLIEST, i] } }
          end

          EARLIEST = Date.new(0)
          private_constant :EARLIEST

          # Visit-level period contract: the visit occurred within the period
          # (inclusive of both endpoints); undated visits always match.
          def within_period?(observation, period)
            date = effective_date(observation)
            date.nil? || period.cover?(date)
          end

          def effective_date(resource)
            value =
              if resource.is_a?(FHIR::Coverage)
                resource.period&.start
              else
                resource.effectiveDateTime
              end
            parse_date(value)
          end

          def parse_date(value)
            return nil if value.nil? || value.to_s.empty?

            Date.parse(value.to_s)
          rescue ArgumentError
            nil
          end

          # Return copies so callers mutating a returned resource cannot
          # corrupt the store; tag provenance on the copies.
          def emit(resources)
            tag_source(resources.map { |r| r.class.new(r.to_hash) })
          end
        end
      end
    end
  end
end
