# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Integrations
    module Clinical
      class ClinicalDataReaderBaseTest < Minitest::Test
        def setup
          @reader = ClinicalDataReader::Base.new
        end

        def test_for_patient_raises_not_implemented
          assert_raises(NotImplementedError) { @reader.for_patient(1, resource_type: "AllergyIntolerance") }
        end

        def test_find_raises_not_implemented
          assert_raises(NotImplementedError) { @reader.find("AllergyIntolerance", "123") }
        end
      end

      class ClinicalDataReaderMockTest < Minitest::Test
        def setup
          @mock = ClinicalDataReader::Mock.new
          @mock.seed(1, "AllergyIntolerance", [
            { ien: "1", allergen: "Penicillin", severity: "high" },
            { ien: "2", allergen: "Aspirin", severity: "low" }
          ])
          @mock.seed(1, "Condition", [
            { ien: "3", display: "Hypertension", code: "I10" }
          ])
        end

        def test_for_patient_returns_seeded_data
          results = @mock.for_patient(1, resource_type: "AllergyIntolerance")
          assert_equal 2, results.length
          assert_equal "Penicillin", results.first[:allergen]
        end

        def test_for_patient_returns_empty_for_unseeded_type
          results = @mock.for_patient(1, resource_type: "Procedure")
          assert_equal [], results
        end

        def test_for_patient_returns_empty_for_unknown_dfn
          results = @mock.for_patient(999, resource_type: "AllergyIntolerance")
          assert_equal [], results
        end

        def test_find_returns_matching_record
          result = @mock.find("AllergyIntolerance", "1")
          assert_equal "Penicillin", result[:allergen]
        end

        def test_find_returns_nil_for_unknown_ien
          assert_nil @mock.find("AllergyIntolerance", "999")
        end

        def test_multiple_resource_types_per_patient
          allergies = @mock.for_patient(1, resource_type: "AllergyIntolerance")
          conditions = @mock.for_patient(1, resource_type: "Condition")
          assert_equal 2, allergies.length
          assert_equal 1, conditions.length
        end
      end
    end
  end
end
