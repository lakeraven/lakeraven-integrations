# frozen_string_literal: true

require "delegate"
require "fhir_models"

module Lakeraven
  module Fhir
    # Lakeraven decorator around FHIR::ClaimResponse.
    #
    # Represents a payer's response to a submitted claim. Wraps a fhir_models
    # FHIR::ClaimResponse and adds Lakeraven-specific accessors (accepted?,
    # success?, claim_id, tracking_number, errors array, paid_amount_cents).
    #
    # FHIR Reference: https://hl7.org/fhir/R4/claimresponse.html
    class ClaimResponse < SimpleDelegator
      def initialize(attributes_or_resource = {})
        if attributes_or_resource.is_a?(::FHIR::ClaimResponse)
          @lakeraven_attrs = {}
          super(attributes_or_resource)
        else
          @lakeraven_attrs = attributes_or_resource
          super(build_fhir(attributes_or_resource))
        end
      end

      # -- Lakeraven accessors --

      def accepted?
        @lakeraven_attrs.fetch(:accepted, outcome == "complete")
      end

      def success?
        accepted?
      end

      def claim_id
        @lakeraven_attrs[:claim_id] || id
      end

      def tracking_number
        @lakeraven_attrs[:tracking_number]
      end

      def errors
        @lakeraven_attrs[:errors] || []
      end

      def patient_dfn
        patient&.reference&.sub(/\APatient\//, "")
      end

      def paid_amount_cents
        @lakeraven_attrs[:paid_amount_cents] || 0
      end

      # -- FHIR hash serialization --

      def to_fhir
        deep_symbolize(__getobj__.to_hash)
      end

      def self.from_fhir(fhir_hash_or_resource)
        resource = if fhir_hash_or_resource.is_a?(::FHIR::ClaimResponse)
          fhir_hash_or_resource
        else
          ::FHIR::ClaimResponse.new(Coverage.stringify_keys(fhir_hash_or_resource))
        end
        new(resource)
      end

      private

      def build_fhir(attrs)
        ::FHIR::ClaimResponse.new(
          id: attrs[:claim_id] || attrs[:id] || SecureRandom.uuid,
          status: "active",
          type: { coding: [{ code: "professional" }] },
          use: "claim",
          patient: attrs[:patient_dfn] ? { reference: "Patient/#{attrs[:patient_dfn]}" } : nil,
          created: Time.now.iso8601,
          insurer: { reference: "Organization/Payer" },
          outcome: attrs[:accepted] ? "complete" : "error",
          disposition: attrs[:accepted] ? "Claim processed" : (attrs[:errors]&.first&.dig(:message) || "Rejected"),
          payment: attrs[:paid_amount_cents] ? { amount: { value: attrs[:paid_amount_cents] / 100.0, currency: "USD" } } : nil,
          error: build_errors(attrs[:errors])
        )
      end

      def build_errors(errors_array)
        return [] unless errors_array&.any?
        errors_array.map { |e| { code: { coding: [{ code: e[:code] || "unknown" }] } } }
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
