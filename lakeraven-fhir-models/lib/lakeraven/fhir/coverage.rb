# frozen_string_literal: true

module Lakeraven
  module Fhir
    # FHIR R4 Coverage resource.
    #
    # Represents insurance or other coverage for a patient. Used to track
    # alternate resources for PRC "payer of last resort" determination and
    # to feed eligibility and claim workflows.
    #
    # FHIR Reference: https://hl7.org/fhir/R4/coverage.html
    class Coverage
      include ActiveModel::Model
      include ActiveModel::Attributes

      # Identification
      attribute :id, :string
      attribute :created_at, :datetime

      # Patient reference
      attribute :patient_dfn, :string

      # Coverage type (medicare_a, medicare_b, medicaid, private_insurance, etc.)
      attribute :coverage_type, :string

      # Status (active, cancelled, draft, entered-in-error, plus PRC workflow states)
      attribute :status, :string, default: "active"

      # Payor information
      attribute :payor_name, :string
      attribute :payor_id, :string
      attribute :payor_type, :string

      # Plan information
      attribute :plan_name, :string
      attribute :plan_id, :string

      # Subscriber information
      attribute :subscriber_id, :string
      attribute :member_id, :string
      attribute :group_id, :string
      attribute :dependent_number, :string

      # Coverage period
      attribute :start_date, :date
      attribute :end_date, :date

      # Relationship to subscriber (self, spouse, child, other)
      attribute :relationship, :string, default: "self"

      # Order for coordination of benefits (1 = primary, 2 = secondary, etc.)
      attribute :order, :integer

      # FHIR statuses plus PRC workflow statuses
      FHIR_STATUSES = %w[active cancelled draft entered-in-error].freeze
      PRC_STATUSES = %w[exhausted not_enrolled denied pending].freeze
      VALID_STATUSES = (FHIR_STATUSES + PRC_STATUSES).freeze

      VALID_COVERAGE_TYPES = %w[
        medicare_a medicare_b medicare_d medicaid private_insurance
        va_benefits workers_comp auto_insurance state_program tribal_program
      ].freeze

      # Validations
      validates :patient_dfn, presence: true
      validates :coverage_type, presence: true
      validates :status, inclusion: { in: VALID_STATUSES }
      validates :coverage_type, inclusion: {
        in: VALID_COVERAGE_TYPES,
        message: "is not a valid coverage type"
      }

      # Initialize with defaults
      def initialize(attributes = {})
        attributes[:id] ||= SecureRandom.uuid
        attributes[:created_at] ||= Time.current
        set_default_payor(attributes)
        super
      end

      # =============================================================================
      # STATUS HELPERS
      # =============================================================================

      def active?
        status == "active" && within_coverage_period?
      end

      def expired?
        end_date.present? && end_date < Date.current
      end

      def cancelled?
        status == "cancelled"
      end

      def within_coverage_period?
        return true unless start_date || end_date
        today = Date.current
        after_start = start_date.nil? || today >= start_date
        before_end = end_date.nil? || today <= end_date
        after_start && before_end
      end

      # =============================================================================
      # PAYOR HELPERS
      # =============================================================================

      def medicare?
        coverage_type&.start_with?("medicare")
      end

      def medicaid?
        coverage_type == "medicaid"
      end

      def private_insurance?
        coverage_type == "private_insurance"
      end

      def va_benefits?
        coverage_type == "va_benefits"
      end

      def government_payer?
        medicare? || medicaid? || va_benefits?
      end

      def payor_display
        payor_name || default_payor_name
      end

      def payor_type_display
        payor_type || default_payor_type
      end

      # =============================================================================
      # COORDINATION OF BENEFITS
      # =============================================================================

      def coordination_order
        order || default_coordination_order
      end

      def primary?
        coordination_order == 1
      end

      def secondary?
        coordination_order == 2
      end

      # =============================================================================
      # FHIR SERIALIZATION
      # =============================================================================

      def to_fhir
        {
          resourceType: "Coverage",
          id: id,
          meta: {
            lastUpdated: created_at&.iso8601
          },
          status: status,
          type: coverage_type_coding,
          subscriber: subscriber_reference,
          beneficiary: {
            reference: "Patient/#{patient_dfn}"
          },
          dependent: dependent_number,
          relationship: relationship_coding,
          period: period_fhir,
          payor: [payor_reference],
          class: class_array,
          order: order
        }.compact
      end

      def self.from_fhir(fhir_hash)
        new(
          id: fhir_hash[:id] || fhir_hash["id"],
          patient_dfn: extract_patient_dfn(fhir_hash),
          status: fhir_hash[:status] || fhir_hash["status"] || "active",
          coverage_type: extract_coverage_type(fhir_hash),
          payor_name: extract_payor_name(fhir_hash),
          **extract_period(fhir_hash),
          **extract_class_info(fhir_hash)
        )
      end

      private

      def set_default_payor(attributes)
        return if attributes[:payor_name].present?

        attributes[:payor_name] = default_payor_name_for(attributes[:coverage_type])
        attributes[:payor_type] = default_payor_type_for(attributes[:coverage_type])
      end

      def default_payor_name
        default_payor_name_for(coverage_type)
      end

      def default_payor_type
        default_payor_type_for(coverage_type)
      end

      def default_payor_name_for(type)
        case type
        when "medicare_a", "medicare_b", "medicare_d" then "Medicare"
        when "medicaid" then "Medicaid"
        when "va_benefits" then "Department of Veterans Affairs"
        when "workers_comp" then "Workers Compensation"
        when "auto_insurance" then "Auto Insurance"
        when "state_program" then "State Health Program"
        when "tribal_program" then "Tribal Health Program"
        when "private_insurance" then "Private Insurance"
        else nil
        end
      end

      def default_payor_type_for(type)
        case type
        when "medicare_a" then "Medicare Part A"
        when "medicare_b" then "Medicare Part B"
        when "medicare_d" then "Medicare Part D"
        when "medicaid" then "Medicaid"
        when "va_benefits" then "VA Benefits"
        when "private_insurance" then "Private Insurance"
        else type&.titleize
        end
      end

      def default_coordination_order
        case coverage_type
        when "private_insurance" then 1
        when "medicare_a", "medicare_b", "medicare_d" then 2
        when "medicaid" then 3
        when "va_benefits" then 2
        when "workers_comp", "auto_insurance" then 1
        else 4
        end
      end

      def coverage_type_coding
        {
          coding: [
            {
              system: "http://terminology.hl7.org/CodeSystem/v3-ActCode",
              code: fhir_coverage_type_code,
              display: payor_type_display
            }
          ]
        }
      end

      def fhir_coverage_type_code
        case coverage_type
        when "medicare_a", "medicare_b", "medicare_d" then "MEDICARE"
        when "medicaid" then "MEDICAID"
        when "private_insurance" then "HIP"
        when "va_benefits" then "VET"
        when "workers_comp" then "WCBPOL"
        when "auto_insurance" then "AUTOPOL"
        else "PUBLICPOL"
        end
      end

      def subscriber_reference
        return nil unless subscriber_id.present?
        { reference: "Patient/#{subscriber_id}" }
      end

      def relationship_coding
        {
          coding: [
            {
              system: "http://terminology.hl7.org/CodeSystem/subscriber-relationship",
              code: relationship || "self"
            }
          ]
        }
      end

      def period_fhir
        return nil unless start_date || end_date
        {
          start: start_date&.iso8601,
          end: end_date&.iso8601
        }.compact
      end

      def payor_reference
        {
          reference: payor_fhir_reference,
          display: payor_display
        }
      end

      def payor_fhir_reference
        case coverage_type
        when "medicare_a", "medicare_b", "medicare_d" then "Organization/CMS"
        when "medicaid" then "Organization/StateMedicaid"
        when "va_benefits" then "Organization/VA"
        else "Organization/#{payor_id || coverage_type&.camelize}"
        end
      end

      def class_array
        classes = []

        if group_id.present?
          classes << {
            type: { coding: [{ system: "http://terminology.hl7.org/CodeSystem/coverage-class", code: "group" }] },
            value: group_id
          }
        end

        if plan_name.present? || plan_id.present?
          classes << {
            type: { coding: [{ system: "http://terminology.hl7.org/CodeSystem/coverage-class", code: "plan" }] },
            value: plan_id || plan_name,
            name: plan_name
          }
        end

        if member_id.present?
          classes << {
            type: { coding: [{ system: "http://terminology.hl7.org/CodeSystem/coverage-class", code: "rxid" }] },
            value: member_id
          }
        end

        classes.presence
      end

      def self.extract_patient_dfn(fhir_hash)
        beneficiary = fhir_hash[:beneficiary] || fhir_hash["beneficiary"]
        return nil unless beneficiary
        reference = beneficiary[:reference] || beneficiary["reference"]
        reference&.gsub("Patient/", "")
      end

      def self.extract_coverage_type(fhir_hash)
        type = fhir_hash[:type] || fhir_hash["type"]
        return nil unless type
        coding = type[:coding]&.first || type["coding"]&.first
        code = coding&.dig(:code) || coding&.dig("code")

        case code
        when "MEDICARE" then "medicare_a"
        when "MEDICAID" then "medicaid"
        when "HIP" then "private_insurance"
        when "VET" then "va_benefits"
        when "WCBPOL" then "workers_comp"
        when "AUTOPOL" then "auto_insurance"
        else "private_insurance"
        end
      end

      def self.extract_payor_name(fhir_hash)
        payors = fhir_hash[:payor] || fhir_hash["payor"]
        return nil unless payors&.any?
        payors.first[:display] || payors.first["display"]
      end

      def self.extract_period(fhir_hash)
        period = fhir_hash[:period] || fhir_hash["period"]
        return {} unless period
        {
          start_date: parse_date(period[:start] || period["start"]),
          end_date: parse_date(period[:end] || period["end"])
        }
      end

      def self.extract_class_info(fhir_hash)
        classes = fhir_hash[:class] || fhir_hash["class"]
        return {} unless classes

        result = {}
        classes.each do |cls|
          type_coding = cls[:type]&.dig(:coding, 0) || cls["type"]&.dig("coding", 0)
          code = type_coding&.dig(:code) || type_coding&.dig("code")

          case code
          when "group"
            result[:group_id] = cls[:value] || cls["value"]
          when "plan"
            result[:plan_name] = cls[:name] || cls["name"]
            result[:plan_id] = cls[:value] || cls["value"]
          when "rxid"
            result[:member_id] = cls[:value] || cls["value"]
          end
        end
        result
      end

      def self.parse_date(value)
        return nil unless value
        Date.parse(value)
      rescue ArgumentError
        nil
      end
    end
  end
end
