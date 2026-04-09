# frozen_string_literal: true

module Lakeraven
  module Fhir
    # FHIR R4 CoverageEligibilityRequest resource.
    #
    # Represents a request to determine coverage eligibility for a patient.
    # Used to query external enrollment services for alternate resource
    # verification and to trigger payer eligibility checks (270 transactions).
    #
    # FHIR Reference: https://hl7.org/fhir/R4/coverageeligibilityrequest.html
    class CoverageEligibilityRequest
      include ActiveModel::Model
      include ActiveModel::Attributes

      # Request identification
      attribute :id, :string
      attribute :created_at, :datetime

      # Patient reference
      attribute :patient_dfn, :string

      # Coverage type being checked
      attribute :coverage_type, :string

      # Service date for eligibility check
      attribute :service_date, :date

      # Purpose of the request
      attribute :purpose, :string, default: "benefits"

      # Requesting provider (optional)
      attribute :provider_ien, :string

      VALID_COVERAGE_TYPES = %w[
        medicare_a medicare_b medicare_d medicaid private_insurance
        va_benefits workers_comp auto_insurance state_program tribal_program
      ].freeze

      # Validations
      validates :patient_dfn, presence: true
      validates :coverage_type, presence: true
      validates :service_date, presence: true
      validates :coverage_type, inclusion: {
        in: VALID_COVERAGE_TYPES,
        message: "is not a valid coverage type"
      }

      # Initialize with defaults
      def initialize(attributes = {})
        attributes[:id] ||= SecureRandom.uuid
        attributes[:created_at] ||= Time.current
        attributes[:service_date] ||= Date.current
        super
      end

      # =============================================================================
      # FHIR SERIALIZATION
      # =============================================================================

      def to_fhir
        {
          resourceType: "CoverageEligibilityRequest",
          id: id,
          meta: {
            lastUpdated: created_at&.iso8601
          },
          status: "active",
          purpose: [purpose],
          patient: {
            reference: "Patient/#{patient_dfn}"
          },
          servicedDate: service_date&.iso8601,
          created: created_at&.iso8601,
          provider: provider_reference,
          insurer: insurer_reference,
          item: [
            {
              category: {
                coding: [coverage_type_coding]
              }
            }
          ]
        }.compact
      end

      def self.from_fhir(fhir_hash)
        new(
          id: fhir_hash[:id] || fhir_hash["id"],
          patient_dfn: extract_patient_dfn(fhir_hash),
          coverage_type: extract_coverage_type(fhir_hash),
          service_date: parse_date(fhir_hash[:servicedDate] || fhir_hash["servicedDate"]),
          purpose: extract_purpose(fhir_hash),
          created_at: parse_datetime(fhir_hash[:created] || fhir_hash["created"])
        )
      end

      private

      def provider_reference
        return nil unless provider_ien.present?
        { reference: "Practitioner/#{provider_ien}" }
      end

      def insurer_reference
        {
          reference: insurer_reference_for_type,
          display: insurer_display_for_type
        }
      end

      def insurer_reference_for_type
        case coverage_type
        when "medicare_a", "medicare_b", "medicare_d"
          "Organization/CMS"
        when "medicaid"
          "Organization/StateMedicaid"
        when "va_benefits"
          "Organization/VA"
        else
          "Organization/#{coverage_type.camelize}"
        end
      end

      def insurer_display_for_type
        case coverage_type
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
        else coverage_type.titleize
        end
      end

      def coverage_type_coding
        {
          system: "http://terminology.hl7.org/CodeSystem/coverage-class",
          code: coverage_type,
          display: insurer_display_for_type
        }
      end

      def self.extract_patient_dfn(fhir_hash)
        patient_ref = fhir_hash[:patient] || fhir_hash["patient"]
        return nil unless patient_ref
        reference = patient_ref[:reference] || patient_ref["reference"]
        reference&.gsub("Patient/", "")
      end

      def self.extract_coverage_type(fhir_hash)
        items = fhir_hash[:item] || fhir_hash["item"]
        return nil unless items&.any?
        category = items.first[:category] || items.first["category"]
        coding = category&.dig(:coding, 0) || category&.dig("coding", 0)
        coding&.dig(:code) || coding&.dig("code")
      end

      def self.extract_purpose(fhir_hash)
        purposes = fhir_hash[:purpose] || fhir_hash["purpose"]
        purposes&.first || "benefits"
      end

      def self.parse_date(value)
        return nil unless value
        Date.parse(value)
      rescue ArgumentError
        nil
      end

      def self.parse_datetime(value)
        return nil unless value
        Time.parse(value)
      rescue ArgumentError
        nil
      end
    end
  end
end
