# frozen_string_literal: true

module Lakeraven
  module Integrations
    module Supplemental
      # The UDS supplemental attribute vocabulary — the contract every per-EHR
      # supplemental adapter normalizes into.
      #
      # UDS reporting needs patient/visit-level attributes that vendor FHIR
      # APIs do not expose; they live in each EHR's registration, eligibility,
      # and billing internals. Adapters reach those internals through whatever
      # non-FHIR access path the platform offers, then emit the values as FHIR
      # Observations coded from this one internal code system, so downstream
      # consumers (SQL-on-FHIR measure evaluation) see a single vocabulary
      # regardless of source EHR.
      #
      # Normalized shape: one FHIR::Observation per attribute value —
      # +code.coding+ = [{system: CODE_SYSTEM, code: <attribute>}], +subject+ =
      # the patient; visit-level attributes also carry an +encounter+
      # reference. Value element by value kind:
      #
      # - :percent -> valueQuantity with UCUM percent unit
      #   ({value:, unit: "%", system: "http://unitsofmeasure.org", code: "%"}).
      #   Whole-percent semantics: 138 means 138% of the federal poverty level.
      # - :coded -> valueCodeableConcept with a single coding from
      #   VALUE_SYSTEM, code drawn from the attribute's +values:+ enumeration.
      #
      # Payer category is deliberately NOT in this vocabulary — it rides as
      # FHIR::Coverage resources (see PayerCategory and
      # DataReader::Base#patient_coverages), not as an Observation.
      module Attributes
        # Internal code system URI for Observation.code on normalized
        # supplemental attributes.
        CODE_SYSTEM = "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-attribute"

        # Internal code system URI for valueCodeableConcept codings on coded
        # attribute values.
        VALUE_SYSTEM = "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-value"

        # Attribute definitions: code => level (:patient or :visit), value
        # kind (:percent or :coded), and — for :coded — the closed +values:+
        # enumeration (codes from VALUE_SYSTEM).
        DEFINITIONS = {
          # Household income as a whole percent of the federal poverty level
          # (basis for UDS income brackets); 138 = 138% FPL.
          "income-percent-fpl" => { level: :patient, value: :percent },
          # Sliding-fee discount class assigned from income/household size.
          "sliding-fee-class" => {
            level: :patient, value: :coded,
            values: %w[class-a class-b class-c class-d class-e].freeze
          },
          # Housing status / homelessness.
          "housing-status" => {
            level: :patient, value: :coded,
            values: %w[housed homeless-shelter doubling-up unsheltered unknown].freeze
          },
          # Migratory / seasonal agricultural worker status.
          "agricultural-worker-status" => {
            level: :patient, value: :coded,
            values: %w[migratory seasonal none].freeze
          },
          # Veteran status.
          "veteran-status" => {
            level: :patient, value: :coded,
            values: %w[veteran non-veteran].freeze
          },
          # Patient best served in a language other than English.
          "language-barrier" => {
            level: :patient, value: :coded,
            values: %w[best-served-other-language english-proficient].freeze
          },
          # UDS service-category classification of a visit.
          "visit-service-category" => {
            level: :visit, value: :coded,
            values: %w[medical dental behavioral-health vision enabling other].freeze
          }
        }.freeze

        ALL = DEFINITIONS.keys.freeze
        PATIENT_LEVEL = DEFINITIONS.select { |_, d| d[:level] == :patient }.keys.freeze
        VISIT_LEVEL = DEFINITIONS.select { |_, d| d[:level] == :visit }.keys.freeze
      end
    end
  end
end
