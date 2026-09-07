# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Integrations
    module Supplemental
      class AttributesTest < Minitest::Test
        def test_code_system_uri
          assert_equal "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-attribute", Attributes::CODE_SYSTEM
        end

        def test_attribute_vocabulary
          expected = %w[
            income_percent_fpl sliding_fee_class payer_category housing_status
            agricultural_worker_status veteran_status language_barrier
            visit_service_category
          ]
          assert_equal expected, Attributes::ALL
        end

        def test_patient_level_attributes
          expected = %w[
            income_percent_fpl sliding_fee_class payer_category housing_status
            agricultural_worker_status veteran_status language_barrier
          ]
          assert_equal expected, Attributes::PATIENT_LEVEL
        end

        def test_visit_level_attributes
          assert_equal %w[visit_service_category], Attributes::VISIT_LEVEL
        end

        def test_every_attribute_has_level_and_value_kind
          Attributes::DEFINITIONS.each do |code, definition|
            assert_includes %i[patient visit], definition[:level], "#{code} level"
            assert_includes %i[percent boolean string], definition[:value], "#{code} value kind"
          end
        end
      end
    end
  end
end
