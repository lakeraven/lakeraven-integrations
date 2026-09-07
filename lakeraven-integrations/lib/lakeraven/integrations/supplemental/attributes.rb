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
      # reference. Value element by value kind: :percent -> valueQuantity
      # (unit "%"), :boolean -> valueBoolean, :string -> valueString.
      module Attributes
        # Internal code system URI for Observation.code on normalized
        # supplemental attributes.
        CODE_SYSTEM = "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-attribute"

        # Attribute definitions: code => level (:patient or :visit) and value
        # kind (:percent, :boolean, :string).
        DEFINITIONS = {
          # Household income as a percent of the federal poverty level
          # (basis for UDS income brackets).
          "income_percent_fpl" => { level: :patient, value: :percent },
          # Sliding-fee discount class assigned from income/household size.
          "sliding_fee_class" => { level: :patient, value: :string },
          # UDS payer category (e.g. medicaid, medicare, private, none) from
          # eligibility/billing internals, distinct from raw coverage records.
          "payer_category" => { level: :patient, value: :string },
          # Housing status / homelessness (e.g. homeless_shelter, doubling_up,
          # street, transitional, permanent_supportive, housed).
          "housing_status" => { level: :patient, value: :string },
          # Migratory / seasonal agricultural worker status
          # (e.g. migratory, seasonal, none).
          "agricultural_worker_status" => { level: :patient, value: :string },
          # Veteran status.
          "veteran_status" => { level: :patient, value: :boolean },
          # Patient best served in a language other than English.
          "language_barrier" => { level: :patient, value: :boolean },
          # UDS service-category classification of a visit (e.g. medical,
          # dental, mental_health, substance_use, vision, enabling).
          "visit_service_category" => { level: :visit, value: :string }
        }.freeze

        ALL = DEFINITIONS.keys.freeze
        PATIENT_LEVEL = DEFINITIONS.select { |_, d| d[:level] == :patient }.keys.freeze
        VISIT_LEVEL = DEFINITIONS.select { |_, d| d[:level] == :visit }.keys.freeze
      end
    end
  end
end
