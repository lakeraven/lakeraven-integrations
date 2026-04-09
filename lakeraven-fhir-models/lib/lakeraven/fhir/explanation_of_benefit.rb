# frozen_string_literal: true

require "delegate"
require "fhir_models"

module Lakeraven
  module Fhir
    # Lakeraven decorator around FHIR::ExplanationOfBenefit.
    #
    # Represents a remittance advice (835 ERA) for a single claim payment.
    # Wraps a fhir_models FHIR::ExplanationOfBenefit and adds
    # Lakeraven-specific accessors (claim_id, paid_amount_cents,
    # patient_responsibility_cents, adjustments, service_lines).
    #
    # FHIR Reference: https://hl7.org/fhir/R4/explanationofbenefit.html
    class ExplanationOfBenefit < SimpleDelegator
      def initialize(attributes_or_resource = {})
        if attributes_or_resource.is_a?(::FHIR::ExplanationOfBenefit)
          @lakeraven_attrs = {}
          super(attributes_or_resource)
        else
          @lakeraven_attrs = attributes_or_resource
          super(build_fhir(attributes_or_resource))
        end
      end

      # -- Lakeraven accessors --

      def claim_id
        @lakeraven_attrs[:claim_id] || id
      end

      def patient_dfn
        patient&.reference&.sub(/\APatient\//, "")
      end

      def paid_amount_cents
        @lakeraven_attrs[:paid_amount_cents] || 0
      end

      def patient_responsibility_cents
        @lakeraven_attrs[:patient_responsibility_cents] || 0
      end

      def adjustments
        @lakeraven_attrs[:adjustments] || []
      end

      def service_lines
        @lakeraven_attrs[:service_lines] || []
      end

      # -- FHIR hash serialization --

      def to_fhir
        deep_symbolize(__getobj__.to_hash)
      end

      def self.from_fhir(fhir_hash_or_resource)
        resource = if fhir_hash_or_resource.is_a?(::FHIR::ExplanationOfBenefit)
          fhir_hash_or_resource
        else
          ::FHIR::ExplanationOfBenefit.new(Coverage.stringify_keys(fhir_hash_or_resource))
        end
        new(resource)
      end

      private

      def build_fhir(attrs)
        ::FHIR::ExplanationOfBenefit.new(
          id: attrs[:id] || SecureRandom.uuid,
          status: "active",
          type: { coding: [{ code: "professional" }] },
          use: "claim",
          patient: attrs[:patient_dfn] ? { reference: "Patient/#{attrs[:patient_dfn]}" } : nil,
          created: Time.now.iso8601,
          insurer: { reference: "Organization/Payer" },
          outcome: "complete",
          payment: attrs[:paid_amount_cents] ? { amount: { value: attrs[:paid_amount_cents] / 100.0, currency: "USD" } } : nil,
          item: build_items(attrs[:service_lines])
        )
      end

      def build_items(service_lines)
        return [] unless service_lines&.any?
        service_lines.each_with_index.map do |line, i|
          {
            sequence: i + 1,
            productOrService: { coding: [{ code: line[:procedure_code] }] },
            adjudication: [
              {
                category: { coding: [{ code: "benefit" }] },
                amount: line[:paid_cents] ? { value: line[:paid_cents] / 100.0, currency: "USD" } : nil
              }.compact
            ]
          }
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
