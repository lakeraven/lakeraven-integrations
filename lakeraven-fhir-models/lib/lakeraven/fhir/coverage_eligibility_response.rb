# frozen_string_literal: true

module Lakeraven
  module Fhir
    # FHIR R4 CoverageEligibilityResponse resource.
    #
    # Represents the response to a coverage eligibility request, indicating
    # whether a patient is enrolled in a particular coverage and the details
    # of the plan. Used downstream to drive PRC "payer of last resort"
    # determination and to populate billing workflows.
    #
    # FHIR Reference: https://hl7.org/fhir/R4/coverageeligibilityresponse.html
    class CoverageEligibilityResponse
      include ActiveModel::Model
      include ActiveModel::Attributes

      # Response identification
      attribute :id, :string
      attribute :created_at, :datetime

      # Request reference
      attribute :request_id, :string

      # Patient reference
      attribute :patient_dfn, :string

      # Coverage type checked
      attribute :coverage_type, :string

      # Enrollment status
      # Values: enrolled, not_enrolled, pending, denied, exhausted, error
      attribute :status, :string

      # Service date
      attribute :service_date, :date

      # Coverage period
      attribute :start_date, :date
      attribute :end_date, :date

      # Plan information
      attribute :plan_name, :string
      attribute :policy_id, :string
      attribute :group_id, :string
      attribute :subscriber_id, :string

      # Insurer information
      attribute :insurer_name, :string
      attribute :insurer_id, :string

      # Response metadata
      attribute :disposition, :string
      attribute :response_data, :string

      VALID_STATUSES = %w[enrolled not_enrolled pending denied exhausted error].freeze

      # Validations
      validates :status, presence: true
      validates :status, inclusion: {
        in: VALID_STATUSES,
        message: "is not a valid status"
      }

      # Initialize with defaults
      def initialize(attributes = {})
        attributes[:id] ||= SecureRandom.uuid
        attributes[:created_at] ||= Time.current
        super
      end

      # =============================================================================
      # STATUS HELPERS
      # =============================================================================

      def enrolled?
        status == "enrolled"
      end

      def not_enrolled?
        status == "not_enrolled"
      end

      def pending?
        status == "pending"
      end

      def denied?
        status == "denied"
      end

      def exhausted?
        status == "exhausted"
      end

      def error?
        status == "error"
      end

      # Final status (no further checks needed)
      def final?
        %w[not_enrolled denied exhausted].include?(status)
      end

      # Coverage is active and can be used as an alternate resource
      def active_coverage?
        enrolled? && within_coverage_period?
      end

      def within_coverage_period?
        return true unless start_date || end_date
        today = Date.current
        after_start = start_date.nil? || today >= start_date
        before_end = end_date.nil? || today <= end_date
        after_start && before_end
      end

      # =============================================================================
      # COVERAGE DETAILS
      # =============================================================================

      def coverage_details
        return nil unless enrolled?
        {
          type: coverage_type,
          status: status,
          period: coverage_period,
          plan: plan_info,
          insurer: insurer_info
        }.compact
      end

      def coverage_period
        return nil unless start_date || end_date
        {
          start: start_date,
          end: end_date
        }.compact
      end

      def plan_info
        return nil unless plan_name || policy_id || group_id
        {
          name: plan_name,
          policy_id: policy_id,
          group_id: group_id,
          subscriber_id: subscriber_id
        }.compact
      end

      def insurer_info
        return nil unless insurer_name || insurer_id
        {
          name: insurer_name,
          id: insurer_id
        }.compact
      end

      # =============================================================================
      # FHIR SERIALIZATION
      # =============================================================================

      def to_fhir
        {
          resourceType: "CoverageEligibilityResponse",
          id: id,
          meta: {
            lastUpdated: created_at&.iso8601
          },
          status: "active",
          purpose: ["benefits"],
          patient: {
            reference: "Patient/#{patient_dfn}"
          },
          servicedDate: service_date&.iso8601,
          created: created_at&.iso8601,
          request: request_reference,
          outcome: fhir_outcome,
          disposition: disposition,
          insurer: fhir_insurer,
          insurance: fhir_insurance
        }.compact
      end

      def self.from_fhir(fhir_hash)
        new(
          id: fhir_hash[:id] || fhir_hash["id"],
          patient_dfn: extract_patient_dfn(fhir_hash),
          request_id: extract_request_id(fhir_hash),
          status: outcome_to_status(
            fhir_hash[:outcome] || fhir_hash["outcome"],
            insurance: fhir_hash[:insurance] || fhir_hash["insurance"]
          ),
          service_date: parse_date(fhir_hash[:servicedDate] || fhir_hash["servicedDate"]),
          created_at: parse_datetime(fhir_hash[:created] || fhir_hash["created"]),
          disposition: fhir_hash[:disposition] || fhir_hash["disposition"],
          **extract_coverage_details(fhir_hash)
        )
      end

      private

      def request_reference
        return nil unless request_id
        { reference: "CoverageEligibilityRequest/#{request_id}" }
      end

      def fhir_outcome
        case status
        when "enrolled", "exhausted" then "complete"
        when "not_enrolled", "denied" then "complete"
        when "pending" then "queued"
        when "error" then "error"
        else "complete"
        end
      end

      def fhir_insurer
        {
          reference: insurer_reference,
          display: insurer_name || coverage_type_display
        }
      end

      def insurer_reference
        case coverage_type
        when "medicare_a", "medicare_b", "medicare_d"
          "Organization/CMS"
        when "medicaid"
          "Organization/StateMedicaid"
        when "va_benefits"
          "Organization/VA"
        else
          "Organization/#{insurer_id || coverage_type&.camelize}"
        end
      end

      def coverage_type_display
        case coverage_type
        when "medicare_a" then "Medicare Part A"
        when "medicare_b" then "Medicare Part B"
        when "medicare_d" then "Medicare Part D"
        when "medicaid" then "Medicaid"
        when "va_benefits" then "VA Benefits"
        when "private_insurance" then "Private Insurance"
        else coverage_type&.titleize
        end
      end

      def fhir_insurance
        return [] unless enrolled?
        [
          {
            coverage: {
              reference: "Coverage/#{patient_dfn}-#{coverage_type}"
            },
            inforce: within_coverage_period?,
            benefitPeriod: benefit_period
          }.compact
        ]
      end

      def benefit_period
        return nil unless start_date || end_date
        {
          start: start_date&.iso8601,
          end: end_date&.iso8601
        }.compact
      end

      def self.extract_patient_dfn(fhir_hash)
        patient_ref = fhir_hash[:patient] || fhir_hash["patient"]
        return nil unless patient_ref
        reference = patient_ref[:reference] || patient_ref["reference"]
        reference&.gsub("Patient/", "")
      end

      def self.extract_request_id(fhir_hash)
        request_ref = fhir_hash[:request] || fhir_hash["request"]
        return nil unless request_ref
        reference = request_ref[:reference] || request_ref["reference"]
        reference&.gsub("CoverageEligibilityRequest/", "")
      end

      def self.outcome_to_status(outcome, insurance: nil)
        case outcome
        when "complete"
          has_active_coverage?(insurance) ? "enrolled" : "not_enrolled"
        when "queued" then "pending"
        when "error" then "error"
        else "not_enrolled"
        end
      end

      def self.has_active_coverage?(insurance)
        return false if insurance.nil? || insurance.empty?

        insurance.any? do |ins|
          ins[:inforce] == true || ins["inforce"] == true
        end
      end

      def self.extract_coverage_details(fhir_hash)
        insurance = (fhir_hash[:insurance] || fhir_hash["insurance"])&.first
        return {} unless insurance

        period = insurance[:benefitPeriod] || insurance["benefitPeriod"]
        {
          start_date: parse_date(period&.dig(:start) || period&.dig("start")),
          end_date: parse_date(period&.dig(:end) || period&.dig("end"))
        }
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
