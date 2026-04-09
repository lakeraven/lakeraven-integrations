# frozen_string_literal: true

require "delegate"
require "active_model"
require "fhir_models"

module Lakeraven
  module Fhir
    # Lakeraven decorator around FHIR::CoverageEligibilityRequest.
    #
    # Represents a request to determine coverage eligibility for a patient.
    # Wraps a fhir_models FHIR::CoverageEligibilityRequest and adds
    # Lakeraven-specific accessors (patient_dfn, coverage_type as Lakeraven
    # enum, provider_ien) and required-field validation.
    #
    # FHIR Reference: https://hl7.org/fhir/R4/coverageeligibilityrequest.html
    class CoverageEligibilityRequest < SimpleDelegator
      include ActiveModel::Validations

      VALID_COVERAGE_TYPES = Coverage::VALID_COVERAGE_TYPES
      LAKERAVEN_TO_FHIR_CODE = Coverage::LAKERAVEN_TO_FHIR_CODE
      FHIR_TO_LAKERAVEN_CODE = Coverage::FHIR_TO_LAKERAVEN_CODE

      validates :patient_dfn, presence: true
      validates :coverage_type, presence: true
      validate :coverage_type_valid

      def initialize(attributes_or_resource = {})
        fhir = if attributes_or_resource.is_a?(::FHIR::CoverageEligibilityRequest)
          @lakeraven_attrs = {}
          attributes_or_resource
        else
          @lakeraven_attrs = attributes_or_resource
          build_fhir(attributes_or_resource)
        end
        super(fhir)
      end

      # -- Lakeraven-flavored accessors --

      def patient_dfn
        ref = patient&.reference
        return nil unless ref
        ref.sub(/\APatient\//, "")
      end

      def coverage_type
        items = item
        return nil unless items&.any?
        coding = items.first.category&.coding&.first
        coding&.code
      end

      def service_date
        value = servicedDate
        return nil if value.nil? || value.to_s.empty?
        value.is_a?(Date) ? value : Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def created_at
        value = meta&.lastUpdated
        return nil if value.nil? || value.to_s.empty?
        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def purpose
        purposes = __getobj__.purpose
        purposes&.first || "benefits"
      end

      def provider_ien
        provider&.reference&.sub(/\APractitioner\//, "")
      end

      # -- Adapter-needed supplemental fields --
      #
      # These are Lakeraven extensions beyond the strict FHIR R4 CER shape,
      # carried on the decorator so adapters (DirectX12, Stedi) have all the
      # data they need to build their vendor payloads. They are NOT serialized
      # into the wrapped FHIR resource; they live in the decorator only.

      def payer_id
        @lakeraven_attrs&.dig(:payer_id)
      end

      def subscriber_id
        @lakeraven_attrs&.dig(:subscriber_id)
      end

      def subscriber_first_name
        @lakeraven_attrs&.dig(:subscriber_first_name)
      end

      def subscriber_last_name
        @lakeraven_attrs&.dig(:subscriber_last_name)
      end

      def subscriber_dob
        @lakeraven_attrs&.dig(:subscriber_dob)
      end

      def provider_npi
        @lakeraven_attrs&.dig(:provider_npi)
      end

      def provider_name
        @lakeraven_attrs&.dig(:provider_name)
      end

      def service_type
        @lakeraven_attrs&.dig(:service_type) || "30"
      end

      # -- FHIR hash serialization (backward compat with tests / consumers) --

      def to_fhir
        deep_symbolize(__getobj__.to_hash)
      end

      def self.from_fhir(fhir_hash_or_resource)
        resource = if fhir_hash_or_resource.is_a?(::FHIR::CoverageEligibilityRequest)
          fhir_hash_or_resource
        else
          ::FHIR::CoverageEligibilityRequest.new(Coverage.stringify_keys(fhir_hash_or_resource))
        end
        new(resource)
      end

      private

      def build_fhir(attrs)
        service_date = attrs[:service_date] || Date.today
        coverage_type_enum = attrs[:coverage_type]
        ::FHIR::CoverageEligibilityRequest.new(
          id: attrs[:id] || SecureRandom.uuid,
          meta: { lastUpdated: (attrs[:created_at] || Time.now).iso8601 },
          status: "active",
          purpose: [attrs[:purpose] || "benefits"],
          patient: attrs[:patient_dfn] ? { reference: "Patient/#{attrs[:patient_dfn]}" } : nil,
          servicedDate: service_date.is_a?(Date) ? service_date.iso8601 : service_date.to_s,
          created: (attrs[:created_at] || Time.now).iso8601,
          provider: attrs[:provider_ien] ? { reference: "Practitioner/#{attrs[:provider_ien]}" } : nil,
          insurer: build_insurer(coverage_type_enum),
          item: coverage_type_enum ? [build_item(coverage_type_enum)] : []
        )
      end

      def build_insurer(coverage_type_enum)
        return nil unless coverage_type_enum
        {
          reference: insurer_reference_for_type(coverage_type_enum),
          display: insurer_display_for_type(coverage_type_enum)
        }
      end

      def insurer_reference_for_type(coverage_type_enum)
        case coverage_type_enum
        when "medicare_a", "medicare_b", "medicare_d"
          "Organization/CMS"
        when "medicaid"
          "Organization/StateMedicaid"
        when "va_benefits"
          "Organization/VA"
        else
          "Organization/#{camelize(coverage_type_enum.to_s)}"
        end
      end

      def insurer_display_for_type(coverage_type_enum)
        case coverage_type_enum
        when "medicare_a" then "Medicare Part A"
        when "medicare_b" then "Medicare Part B"
        when "medicare_d" then "Medicare Part D"
        when "medicaid" then "Medicaid"
        when "va_benefits" then "VA Benefits"
        when "private_insurance" then "Private Insurance"
        when "workers_comp" then "Workers Compensation"
        when "auto_insurance" then "Auto Insurance"
        when "state_program" then "State Health Program"
        when "tribal_program" then "Tribal Health Program"
        else camelize(coverage_type_enum.to_s)
        end
      end

      def build_item(coverage_type_enum)
        {
          category: {
            coding: [
              {
                system: "http://terminology.hl7.org/CodeSystem/coverage-class",
                code: coverage_type_enum,
                display: insurer_display_for_type(coverage_type_enum)
              }
            ]
          }
        }
      end

      def camelize(str)
        str.split("_").map(&:capitalize).join
      end

      def coverage_type_valid
        return if coverage_type.nil?
        unless VALID_COVERAGE_TYPES.include?(coverage_type)
          errors.add(:coverage_type, "is not a valid coverage type")
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
