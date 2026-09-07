# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Integrations
    module Supplemental
      class DataReaderBaseTest < Minitest::Test
        def setup
          @reader = DataReader::Base.new
        end

        def test_source_descriptor_raises_not_implemented
          assert_raises(NotImplementedError) { @reader.source_descriptor }
        end

        def test_patient_attributes_raises_not_implemented
          assert_raises(NotImplementedError) { @reader.patient_attributes(["1"]) }
        end

        def test_visit_attributes_raises_not_implemented
          assert_raises(NotImplementedError) { @reader.visit_attributes(["1"]) }
        end
      end

      class DataReaderMockTest < Minitest::Test
        def setup
          @descriptor = SourceDescriptor.new(id: "site-a", ehr_platform: "rpms", channel: "supplemental")
          @mock = DataReader::Mock.new(source_descriptor: @descriptor)
        end

        def test_default_descriptor_is_supplemental
          descriptor = DataReader::Mock.new.source_descriptor

          assert_instance_of SourceDescriptor, descriptor
          assert descriptor.supplemental?
        end

        def test_exposes_configured_source_descriptor
          assert_equal @descriptor, @mock.source_descriptor
        end

        # -- Normalized observation shape --

        def test_patient_attribute_normalizes_to_coded_observation
          @mock.seed_patient_attribute("1", "housing_status", "homeless_shelter")

          observation = @mock.patient_attributes(["1"]).first

          assert_instance_of FHIR::Observation, observation
          coding = observation.code.coding.first
          assert_equal Attributes::CODE_SYSTEM, coding.system
          assert_equal "housing_status", coding.code
          assert_equal "Patient/1", observation.subject.reference
          assert_equal "homeless_shelter", observation.valueString
          assert_nil observation.encounter
        end

        def test_percent_attribute_uses_value_quantity
          @mock.seed_patient_attribute("1", "income_percent_fpl", 138)

          observation = @mock.patient_attributes(["1"]).first

          assert_equal 138, observation.valueQuantity.value
          assert_equal "%", observation.valueQuantity.unit
        end

        def test_boolean_attribute_uses_value_boolean
          @mock.seed_patient_attribute("1", "veteran_status", true)

          observation = @mock.patient_attributes(["1"]).first

          assert_equal true, observation.valueBoolean
        end

        def test_visit_attribute_carries_encounter_reference
          @mock.seed_visit_attribute("1", "enc-9", "visit_service_category", "dental",
                                     effective: Date.new(2026, 3, 5))

          observation = @mock.visit_attributes(["1"]).first

          assert_equal "Encounter/enc-9", observation.encounter.reference
          assert_equal "visit_service_category", observation.code.coding.first.code
          assert_equal "dental", observation.valueString
        end

        def test_seed_rejects_unknown_attribute
          assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "shoe_size", "11") }
        end

        def test_seed_rejects_attribute_at_wrong_level
          assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "visit_service_category", "medical") }
          assert_raises(ArgumentError) { @mock.seed_visit_attribute("1", "enc-1", "veteran_status", true) }
        end

        # -- Reads --

        def test_reads_cohort_across_patients
          @mock.seed_patient_attribute("1", "payer_category", "medicaid")
          @mock.seed_patient_attribute("2", "payer_category", "none")

          results = @mock.patient_attributes(%w[1 2])

          assert_equal %w[Patient/1 Patient/2], results.map { |o| o.subject.reference }
        end

        def test_accepts_single_patient_id
          @mock.seed_patient_attribute("1", "language_barrier", true)

          assert_equal 1, @mock.patient_attributes("1").length
        end

        def test_returns_empty_for_unknown_patient
          assert_equal [], @mock.patient_attributes(["999"])
        end

        def test_filters_by_period
          @mock.seed_patient_attribute("1", "sliding_fee_class", "A", effective: Date.new(2025, 2, 1))
          @mock.seed_patient_attribute("1", "sliding_fee_class", "B", effective: Date.new(2026, 2, 1))

          results = @mock.patient_attributes(["1"], period: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))

          assert_equal ["B"], results.map(&:valueString)
        end

        def test_undated_attributes_pass_period_filter
          @mock.seed_patient_attribute("1", "agricultural_worker_status", "seasonal")

          results = @mock.patient_attributes(["1"], period: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))

          assert_equal ["seasonal"], results.map(&:valueString)
        end

        # -- Provenance --

        def test_tags_meta_source_from_descriptor
          @mock.seed_patient_attribute("1", "veteran_status", false)
          @mock.seed_visit_attribute("1", "enc-1", "visit_service_category", "medical")

          (@mock.patient_attributes(["1"]) + @mock.visit_attributes(["1"])).each do |observation|
            assert_equal "urn:lakeraven:source:site-a", observation.meta.source
          end
        end
      end

      # -- Lakeraven::Integrations configuration registry --

      class SupplementalConfigurationTest < Minitest::Test
        def teardown
          Lakeraven::Integrations.reset_configuration!
        end

        def test_defaults_to_empty_array
          assert_equal [], Lakeraven::Integrations.supplemental_data_readers
        end

        def test_configure_registers_multiple_readers
          site_a = DataReader::Mock.new(
            source_descriptor: SourceDescriptor.new(id: "site-a", ehr_platform: "rpms", channel: "supplemental")
          )
          site_b = DataReader::Mock.new(
            source_descriptor: SourceDescriptor.new(id: "site-b", ehr_platform: "epic", channel: "supplemental")
          )

          Lakeraven::Integrations.configure do |config|
            config.supplemental_data_readers = [site_a, site_b]
          end

          assert_equal [site_a, site_b], Lakeraven::Integrations.supplemental_data_readers
          assert Lakeraven::Integrations.supplemental_data_readers.all? { |r| r.source_descriptor.supplemental? }
        end

        def test_reset_configuration_clears_readers
          Lakeraven::Integrations.configure { |c| c.supplemental_data_readers = [DataReader::Mock.new] }
          Lakeraven::Integrations.reset_configuration!

          assert_equal [], Lakeraven::Integrations.supplemental_data_readers
        end
      end
    end
  end
end
