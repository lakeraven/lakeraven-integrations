# frozen_string_literal: true

require "delegate"
require "fhir_models"

module Lakeraven
  module Fhir
    # Lakeraven decorator around FHIR::Claim.
    #
    # Wraps a fhir_models FHIR::Claim and adds Lakeraven-specific PRC
    # workflow accessors (claim_type as "837P"/"837I", procedure_codes
    # with charge_cents, revenue_codes, patient/provider/subscriber
    # fields adapters need for payload construction).
    #
    # FHIR Reference: https://hl7.org/fhir/R4/claim.html
    class Claim < SimpleDelegator
      CLAIM_TYPE_MAP = {
        "837P" => "professional",
        "837I" => "institutional",
        "837D" => "oral"
      }.freeze

      FHIR_TO_CLAIM_TYPE = CLAIM_TYPE_MAP.invert.freeze

      def initialize(attributes_or_resource = {})
        if attributes_or_resource.is_a?(::FHIR::Claim)
          @lakeraven_attrs = {}
          super(attributes_or_resource)
        else
          @lakeraven_attrs = attributes_or_resource
          super(build_fhir(attributes_or_resource))
        end
      end

      # -- Lakeraven accessors --

      def claim_type
        @lakeraven_attrs[:claim_type] || FHIR_TO_CLAIM_TYPE[type&.coding&.first&.code] || "837P"
      end

      def patient_dfn
        patient&.reference&.sub(/\APatient\//, "")
      end

      def professional?
        claim_type == "837P"
      end

      def institutional?
        claim_type == "837I"
      end

      def payer_id
        @lakeraven_attrs[:payer_id]
      end

      def subscriber_id
        @lakeraven_attrs[:subscriber_id]
      end

      def patient_first_name
        @lakeraven_attrs[:patient_first_name]
      end

      def patient_last_name
        @lakeraven_attrs[:patient_last_name]
      end

      def patient_dob
        @lakeraven_attrs[:patient_dob]
      end

      def provider_npi
        @lakeraven_attrs[:provider_npi]
      end

      def provider_tax_id
        @lakeraven_attrs[:provider_tax_id]
      end

      def facility_npi
        @lakeraven_attrs[:facility_npi]
      end

      def service_date
        @lakeraven_attrs[:service_date]
      end

      def diagnosis_codes
        @lakeraven_attrs[:diagnosis_codes] || []
      end

      def procedure_codes
        @lakeraven_attrs[:procedure_codes] || []
      end

      def revenue_codes
        @lakeraven_attrs[:revenue_codes] || []
      end

      def place_of_service
        @lakeraven_attrs[:place_of_service] || "11"
      end

      def type_of_bill
        @lakeraven_attrs[:type_of_bill]
      end

      def total_charge_cents
        @lakeraven_attrs[:total_charge_cents] || 0
      end

      # -- FHIR hash serialization --

      def to_fhir
        deep_symbolize(__getobj__.to_hash)
      end

      def self.from_fhir(fhir_hash_or_resource)
        resource = if fhir_hash_or_resource.is_a?(::FHIR::Claim)
          fhir_hash_or_resource
        else
          ::FHIR::Claim.new(Coverage.stringify_keys(fhir_hash_or_resource))
        end
        new(resource)
      end

      private

      def build_fhir(attrs)
        ::FHIR::Claim.new(
          id: attrs[:id] || SecureRandom.uuid,
          status: "active",
          type: { coding: [{ code: CLAIM_TYPE_MAP[attrs[:claim_type]] || "professional" }] },
          use: "claim",
          patient: attrs[:patient_dfn] ? { reference: "Patient/#{attrs[:patient_dfn]}" } : nil,
          created: Time.now.iso8601,
          provider: attrs[:provider_npi] ? { reference: "Practitioner/#{attrs[:provider_npi]}" } : nil,
          priority: { coding: [{ code: "normal" }] },
          diagnosis: build_diagnosis(attrs[:diagnosis_codes]),
          item: build_items(attrs),
          total: attrs[:total_charge_cents] ? { value: attrs[:total_charge_cents] / 100.0, currency: "USD" } : nil
        )
      end

      def build_diagnosis(codes)
        return [] unless codes
        codes.each_with_index.map do |code, i|
          { sequence: i + 1, diagnosisCodeableConcept: { coding: [{ code: code }] } }
        end
      end

      def build_items(attrs)
        codes = attrs[:procedure_codes] || attrs[:revenue_codes] || []
        codes.each_with_index.map do |entry, i|
          {
            sequence: i + 1,
            productOrService: { coding: [{ code: entry[:code] }] },
            quantity: entry[:units] ? { value: entry[:units] } : nil,
            unitPrice: entry[:charge_cents] ? { value: entry[:charge_cents] / 100.0, currency: "USD" } : nil
          }.compact
        end
      end

      def deep_symbolize(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), out| out[k.to_sym] = deep_symbolize(v) }
        when Array
          obj.map { |e| deep_symbolize(e) }
        else
          obj
        end
      end
    end
  end
end
