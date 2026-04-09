# frozen_string_literal: true

require "delegate"
require "active_model"
require "fhir_models"

module Lakeraven
  module Fhir
    # Lakeraven decorator around FHIR::Coverage.
    #
    # Wraps a fhir_models FHIR::Coverage resource (the FHIR-R4-spec-correct
    # representation) and adds Lakeraven-specific PRC workflow behavior:
    # coverage-type classification (medicare?, medicaid?, government_payer?),
    # coordination-of-benefits defaults ("payer of last resort" ordering),
    # Lakeraven-level required-field validation, and convenience accessors
    # that read Lakeraven-flavored values out of the underlying FHIR shape
    # (patient_dfn, coverage_type string enum, plan/group/member IDs, etc.).
    #
    # The goal is to stay aligned with FHIR R4 for wire format while
    # keeping PRC-specific logic co-located with the resource.
    #
    # FHIR Reference: https://hl7.org/fhir/R4/coverage.html
    class Coverage < SimpleDelegator
      include ActiveModel::Validations

      FHIR_STATUSES = %w[active cancelled draft entered-in-error].freeze
      PRC_STATUSES = %w[exhausted not_enrolled denied pending].freeze
      VALID_STATUSES = (FHIR_STATUSES + PRC_STATUSES).freeze

      VALID_COVERAGE_TYPES = %w[
        medicare_a medicare_b medicare_d medicaid private_insurance
        va_benefits workers_comp auto_insurance state_program tribal_program
      ].freeze

      # Map Lakeraven coverage type enum <-> FHIR v3-ActCode
      LAKERAVEN_TO_FHIR_CODE = {
        "medicare_a" => "MEDICARE",
        "medicare_b" => "MEDICARE",
        "medicare_d" => "MEDICARE",
        "medicaid" => "MEDICAID",
        "private_insurance" => "HIP",
        "va_benefits" => "VET",
        "workers_comp" => "WCBPOL",
        "auto_insurance" => "AUTOPOL",
        "state_program" => "PUBLICPOL",
        "tribal_program" => "PUBLICPOL"
      }.freeze

      FHIR_TO_LAKERAVEN_CODE = {
        "MEDICARE" => "medicare_a",
        "MEDICAID" => "medicaid",
        "HIP" => "private_insurance",
        "VET" => "va_benefits",
        "WCBPOL" => "workers_comp",
        "AUTOPOL" => "auto_insurance",
        "PUBLICPOL" => "private_insurance"
      }.freeze

      validates :patient_dfn, presence: true
      validates :coverage_type, presence: true
      validate :coverage_type_valid
      validate :status_valid

      # Construct from Lakeraven-shaped attributes (builds a FHIR::Coverage
      # underneath) or wrap an existing FHIR::Coverage instance.
      def initialize(attributes_or_resource = {})
        fhir = if attributes_or_resource.is_a?(::FHIR::Coverage)
          attributes_or_resource
        else
          build_fhir(attributes_or_resource)
        end
        super(fhir)
      end

      # -- Lakeraven-flavored accessors --

      def patient_dfn
        ref = beneficiary&.reference
        return nil unless ref
        ref.sub(/\APatient\//, "")
      end

      def coverage_type
        coding = type&.coding&.first
        return nil unless coding
        # Display is set to the Lakeraven enum by build_fhir. Prefer it as
        # the source of truth so validation catches invalid inputs (otherwise
        # the FHIR code round-trip would silently remap them).
        coding.display || FHIR_TO_LAKERAVEN_CODE[coding.code]
      end

      def relationship
        __getobj__.relationship&.coding&.first&.code
      end

      def created_at
        value = meta&.lastUpdated
        return nil if value.nil? || value.to_s.empty?
        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def payor_name
        payor&.first&.display
      end

      def payor_display
        payor_name || default_payor_name
      end

      def plan_name
        lookup_class_value("plan", :name)
      end

      def plan_id
        lookup_class_value("plan", :value)
      end

      def group_id
        lookup_class_value("group", :value)
      end

      def member_id
        lookup_class_value("rxid", :value)
      end

      def start_date
        parse_date(period&.start)
      end

      def end_date
        parse_date(period&.end)
      end

      # -- Status helpers --

      def active?
        status == "active" && within_coverage_period?
      end

      def expired?
        end_date && end_date < Date.today
      end

      def cancelled?
        status == "cancelled"
      end

      def within_coverage_period?
        return true unless start_date || end_date
        today = Date.today
        (start_date.nil? || today >= start_date) &&
          (end_date.nil? || today <= end_date)
      end

      # -- Payor helpers --

      def medicare?
        coverage_type&.start_with?("medicare") || false
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

      # -- Coordination of benefits --

      def coordination_order
        order || default_coordination_order
      end

      def primary?
        coordination_order == 1
      end

      def secondary?
        coordination_order == 2
      end

      # -- Serialize to a symbol-keyed FHIR hash --

      def to_fhir
        deep_symbolize(__getobj__.to_hash)
      end

      # -- Reconstruct from a FHIR hash or FHIR::Coverage --

      def self.from_fhir(fhir_hash_or_resource)
        resource = if fhir_hash_or_resource.is_a?(::FHIR::Coverage)
          fhir_hash_or_resource
        else
          ::FHIR::Coverage.new(stringify_keys(fhir_hash_or_resource))
        end
        new(resource)
      end

      def self.stringify_keys(hash)
        hash.each_with_object({}) do |(k, v), out|
          out[k.to_s] = v.is_a?(Hash) ? stringify_keys(v) : v.is_a?(Array) ? v.map { |e| e.is_a?(Hash) ? stringify_keys(e) : e } : v
        end
      end

      private

      def build_fhir(attrs)
        coverage_type_enum = attrs[:coverage_type]
        ::FHIR::Coverage.new(
          id: attrs[:id] || SecureRandom.uuid,
          meta: { lastUpdated: (attrs[:created_at] || Time.now).iso8601 },
          status: attrs[:status] || "active",
          type: build_type(coverage_type_enum),
          beneficiary: attrs[:patient_dfn] ? { reference: "Patient/#{attrs[:patient_dfn]}" } : nil,
          subscriber: attrs[:subscriber_id] ? { reference: "Patient/#{attrs[:subscriber_id]}" } : nil,
          dependent: attrs[:dependent_number],
          relationship: build_relationship(attrs[:relationship] || "self"),
          period: build_period(attrs[:start_date], attrs[:end_date]),
          payor: [build_payor(coverage_type_enum, attrs[:payor_name], attrs[:payor_id])],
          local_class: build_class_array(
            group_id: attrs[:group_id],
            plan_name: attrs[:plan_name],
            plan_id: attrs[:plan_id],
            member_id: attrs[:member_id]
          ),
          order: attrs[:order]
        )
      end

      def build_type(coverage_type_enum)
        return nil unless coverage_type_enum
        {
          coding: [
            {
              system: "http://terminology.hl7.org/CodeSystem/v3-ActCode",
              code: LAKERAVEN_TO_FHIR_CODE[coverage_type_enum] || "PUBLICPOL",
              display: coverage_type_enum
            }
          ]
        }
      end

      def build_relationship(relationship_code)
        {
          coding: [
            {
              system: "http://terminology.hl7.org/CodeSystem/subscriber-relationship",
              code: relationship_code
            }
          ]
        }
      end

      def build_period(start_date, end_date)
        return nil unless start_date || end_date
        {
          start: format_date(start_date),
          end: format_date(end_date)
        }.compact
      end

      def build_payor(coverage_type_enum, explicit_name, explicit_id)
        name = explicit_name || default_payor_name_for(coverage_type_enum)
        {
          reference: payor_fhir_reference(coverage_type_enum, explicit_id),
          display: name
        }
      end

      def payor_fhir_reference(coverage_type_enum, explicit_id)
        case coverage_type_enum
        when "medicare_a", "medicare_b", "medicare_d" then "Organization/CMS"
        when "medicaid" then "Organization/StateMedicaid"
        when "va_benefits" then "Organization/VA"
        else "Organization/#{explicit_id || camelize(coverage_type_enum.to_s)}"
        end
      end

      def build_class_array(group_id:, plan_name:, plan_id:, member_id:)
        classes = []
        if group_id && !group_id.empty?
          classes << {
            type: { coding: [{ system: "http://terminology.hl7.org/CodeSystem/coverage-class", code: "group" }] },
            value: group_id
          }
        end
        if (plan_name && !plan_name.empty?) || (plan_id && !plan_id.empty?)
          classes << {
            type: { coding: [{ system: "http://terminology.hl7.org/CodeSystem/coverage-class", code: "plan" }] },
            value: plan_id || plan_name,
            name: plan_name
          }
        end
        if member_id && !member_id.empty?
          classes << {
            type: { coding: [{ system: "http://terminology.hl7.org/CodeSystem/coverage-class", code: "rxid" }] },
            value: member_id
          }
        end
        classes
      end

      def lookup_class_value(target_code, field)
        return nil unless local_class
        entry = local_class.find do |cls|
          cls.type&.coding&.first&.code == target_code
        end
        return nil unless entry
        field == :name ? entry.name : entry.value
      end

      def default_payor_name
        default_payor_name_for(coverage_type)
      end

      def default_payor_name_for(type_enum)
        case type_enum
        when "medicare_a", "medicare_b", "medicare_d" then "Medicare"
        when "medicaid" then "Medicaid"
        when "va_benefits" then "Department of Veterans Affairs"
        when "workers_comp" then "Workers Compensation"
        when "auto_insurance" then "Auto Insurance"
        when "state_program" then "State Health Program"
        when "tribal_program" then "Tribal Health Program"
        when "private_insurance" then "Private Insurance"
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

      def parse_date(value)
        return nil if value.nil? || value.to_s.empty?
        value.is_a?(Date) ? value : Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def format_date(value)
        return nil if value.nil?
        value.is_a?(Date) ? value.iso8601 : value.to_s
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
