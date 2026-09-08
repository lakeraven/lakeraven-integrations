# frozen_string_literal: true

require "delegate"
require "active_model"
require "fhir_models"

module Lakeraven
  module Fhir
    # Lakeraven decorator around FHIR::CoverageEligibilityResponse.
    #
    # Wraps a fhir_models resource and adds Lakeraven-specific PRC workflow
    # behavior: enrolled/not_enrolled/pending/denied/exhausted/error statuses
    # (mapped to FHIR outcomes), active_coverage? lifecycle helpers, and
    # coverage_details / plan_info / insurer_info structured accessors for
    # downstream PRC decision logic.
    #
    # FHIR Reference: https://hl7.org/fhir/R4/coverageeligibilityresponse.html
    class CoverageEligibilityResponse < SimpleDelegator
      include ActiveModel::Validations

      VALID_STATUSES = %w[enrolled not_enrolled pending denied exhausted error].freeze

      validates :status, presence: true
      validate :status_valid

      def initialize(attributes_or_resource = {})
        fhir = if attributes_or_resource.is_a?(::FHIR::CoverageEligibilityResponse)
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

      def request_id
        ref = request&.reference
        return nil unless ref
        ref.sub(/\ACoverageEligibilityRequest\//, "")
      end

      def coverage_type
        @lakeraven_attrs&.dig(:coverage_type)
      end

      def service_date
        parse_date(servicedDate)
      end

      def start_date
        parse_date(insurance&.first&.benefitPeriod&.start)
      end

      def end_date
        parse_date(insurance&.first&.benefitPeriod&.end)
      end

      def plan_name
        @lakeraven_attrs&.dig(:plan_name)
      end

      def policy_id
        @lakeraven_attrs&.dig(:policy_id)
      end

      def group_id
        @lakeraven_attrs&.dig(:group_id)
      end

      def subscriber_id
        @lakeraven_attrs&.dig(:subscriber_id)
      end

      def insurer_name
        insurer&.display
      end

      def insurer_id
        @lakeraven_attrs&.dig(:insurer_id)
      end

      def disposition
        __getobj__.disposition
      end

      def created_at
        value = meta&.lastUpdated
        return nil if value.nil? || value.to_s.empty?
        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      # -- Status helpers --

      def status
        @status ||= @lakeraven_attrs&.dig(:status) || outcome_to_status
      end

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

      # Final status — no further checks needed
      def final?
        %w[not_enrolled denied exhausted].include?(status)
      end

      # Coverage is active and can be used as an alternate resource
      def active_coverage?
        enrolled? && within_coverage_period?
      end

      def within_coverage_period?
        return true unless start_date || end_date
        today = Date.today
        (start_date.nil? || today >= start_date) &&
          (end_date.nil? || today <= end_date)
      end

      # -- Coverage details --

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
        { start: start_date, end: end_date }.compact
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
        { name: insurer_name, id: insurer_id }.compact
      end

      # -- FHIR hash serialization --

      def to_fhir
        deep_symbolize(__getobj__.to_hash)
      end

      def self.from_fhir(fhir_hash_or_resource)
        resource = if fhir_hash_or_resource.is_a?(::FHIR::CoverageEligibilityResponse)
          fhir_hash_or_resource
        else
          ::FHIR::CoverageEligibilityResponse.new(Coverage.stringify_keys(fhir_hash_or_resource))
        end
        instance = new(resource)
        # Derive Lakeraven status from FHIR outcome + insurance.inforce
        instance.send(:set_status_from_fhir)
        instance
      end

      private

      def build_fhir(attrs)
        ::FHIR::CoverageEligibilityResponse.new(
          id: attrs[:id] || SecureRandom.uuid,
          meta: { lastUpdated: (attrs[:created_at] || Time.now).iso8601 },
          status: "active",
          purpose: ["benefits"],
          patient: attrs[:patient_dfn] ? { reference: "Patient/#{attrs[:patient_dfn]}" } : { reference: "Patient/unknown" },
          servicedDate: attrs[:service_date] ? format_date(attrs[:service_date]) : nil,
          created: (attrs[:created_at] || Time.now).iso8601,
          request: attrs[:request_id] ? { reference: "CoverageEligibilityRequest/#{attrs[:request_id]}" } : nil,
          outcome: fhir_outcome_for(attrs[:status]),
          disposition: attrs[:disposition],
          insurer: build_insurer(attrs),
          insurance: build_insurance(attrs)
        )
      end

      def fhir_outcome_for(status)
        case status
        when "enrolled", "exhausted", "not_enrolled", "denied" then "complete"
        when "pending" then "queued"
        when "error" then "error"
        else nil
        end
      end

      def build_insurer(attrs)
        name = attrs[:insurer_name] || coverage_type_display(attrs[:coverage_type])
        {
          reference: insurer_reference_for(attrs[:coverage_type], attrs[:insurer_id]),
          display: name
        }
      end

      def insurer_reference_for(coverage_type, insurer_id)
        case coverage_type
        when "medicare_a", "medicare_b", "medicare_d" then "Organization/CMS"
        when "medicaid" then "Organization/StateMedicaid"
        when "va_benefits" then "Organization/VA"
        else "Organization/#{insurer_id || camelize(coverage_type.to_s)}"
        end
      end

      def coverage_type_display(coverage_type)
        case coverage_type
        when "medicare_a" then "Medicare Part A"
        when "medicare_b" then "Medicare Part B"
        when "medicare_d" then "Medicare Part D"
        when "medicaid" then "Medicaid"
        when "va_benefits" then "VA Benefits"
        when "private_insurance" then "Private Insurance"
        else camelize(coverage_type.to_s)
        end
      end

      def build_insurance(attrs)
        return [] unless attrs[:status] == "enrolled"
        [
          {
            coverage: {
              reference: "Coverage/#{attrs[:patient_dfn]}-#{attrs[:coverage_type]}"
            },
            inforce: within_period_for(attrs[:start_date], attrs[:end_date]),
            benefitPeriod: build_benefit_period(attrs[:start_date], attrs[:end_date])
          }.compact
        ]
      end

      def within_period_for(start_date, end_date)
        return true unless start_date || end_date
        today = Date.today
        (start_date.nil? || today >= start_date) &&
          (end_date.nil? || today <= end_date)
      end

      def build_benefit_period(start_date, end_date)
        return nil unless start_date || end_date
        { start: format_date(start_date), end: format_date(end_date) }.compact
      end

      def format_date(value)
        return nil if value.nil?
        value.is_a?(Date) ? value.iso8601 : value.to_s
      end

      def parse_date(value)
        return nil if value.nil? || value.to_s.empty?
        value.is_a?(Date) ? value : Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def outcome_to_status
        fhir_outcome = __getobj__.outcome
        return nil unless fhir_outcome
        case fhir_outcome
        when "complete"
          has_active_coverage? ? "enrolled" : "not_enrolled"
        when "queued" then "pending"
        when "error" then "error"
        else "not_enrolled"
        end
      end

      def has_active_coverage?
        ins = __getobj__.insurance
        return false if ins.nil? || ins.empty?
        ins.any? { |entry| entry.inforce == true }
      end

      def set_status_from_fhir
        @status = outcome_to_status
      end

      def camelize(str)
        str.split("_").map(&:capitalize).join
      end

      def status_valid
        return if status.nil?
        unless VALID_STATUSES.include?(status)
          errors.add(:status, "is not a valid status")
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
