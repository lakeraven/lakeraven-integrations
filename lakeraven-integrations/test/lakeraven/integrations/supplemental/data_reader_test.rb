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

        def test_patient_coverages_raises_not_implemented
          assert_raises(NotImplementedError) { @reader.patient_coverages(["1"]) }
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
          @mock.seed_patient_attribute("1", "housing-status", "homeless-shelter")

          observation = @mock.patient_attributes(["1"]).first

          assert_instance_of FHIR::Observation, observation
          coding = observation.code.coding.first
          assert_equal Attributes::CODE_SYSTEM, coding.system
          assert_equal "housing-status", coding.code
          assert_equal "Patient/1", observation.subject.reference
          value_coding = observation.valueCodeableConcept.coding.first
          assert_equal Attributes::VALUE_SYSTEM, value_coding.system
          assert_equal "homeless-shelter", value_coding.code
          assert_nil observation.encounter
        end

        def test_percent_attribute_uses_ucum_value_quantity
          @mock.seed_patient_attribute("1", "income-percent-fpl", 138)

          observation = @mock.patient_attributes(["1"]).first

          # Whole-percent semantics: 138 = 138% FPL.
          assert_equal 138, observation.valueQuantity.value
          assert_equal "%", observation.valueQuantity.unit
          assert_equal "http://unitsofmeasure.org", observation.valueQuantity.system
          assert_equal "%", observation.valueQuantity.code
        end

        def test_veteran_status_uses_value_codeable_concept
          @mock.seed_patient_attribute("1", "veteran-status", "veteran")

          observation = @mock.patient_attributes(["1"]).first

          assert_nil observation.valueBoolean
          assert_nil observation.valueString
          assert_equal "veteran", observation.valueCodeableConcept.coding.first.code
        end

        def test_visit_attribute_carries_encounter_reference
          @mock.seed_visit_attribute("1", "enc-9", "visit-service-category", "dental",
                                     effective: Date.new(2026, 3, 5))

          observation = @mock.visit_attributes(["1"]).first

          assert_equal "Encounter/enc-9", observation.encounter.reference
          assert_equal "visit-service-category", observation.code.coding.first.code
          assert_equal "dental", observation.valueCodeableConcept.coding.first.code
        end

        # -- Seed validation --

        def test_seed_rejects_unknown_attribute
          assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "shoe-size", "11") }
        end

        def test_seed_rejects_attribute_at_wrong_level
          assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "visit-service-category", "medical") }
          assert_raises(ArgumentError) { @mock.seed_visit_attribute("1", "enc-1", "veteran-status", "veteran") }
        end

        def test_seed_rejects_value_outside_enumeration
          error = assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "housing-status", "condo") }
          assert_match(/housing-status value must be one of/, error.message)

          assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "veteran-status", true) }
          assert_raises(ArgumentError) { @mock.seed_visit_attribute("1", "enc-1", "visit-service-category", "spa") }
        end

        def test_seed_rejects_mistyped_percent_value
          error = assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "income-percent-fpl", "138") }
          assert_match(/must be Numeric/, error.message)
        end

        # -- Reads --

        def test_reads_cohort_across_patients
          @mock.seed_patient_attribute("1", "sliding-fee-class", "class-a")
          @mock.seed_patient_attribute("2", "sliding-fee-class", "class-b")

          results = @mock.patient_attributes(%w[1 2])

          assert_equal %w[Patient/1 Patient/2], results.map { |o| o.subject.reference }
        end

        def test_accepts_single_patient_id
          @mock.seed_patient_attribute("1", "language-barrier", "best-served-other-language")

          assert_equal 1, @mock.patient_attributes("1").length
        end

        def test_returns_empty_for_unknown_patient
          assert_equal [], @mock.patient_attributes(["999"])
        end

        def test_returned_resources_are_copies_of_the_store
          @mock.seed_patient_attribute("1", "veteran-status", "veteran")

          @mock.patient_attributes(["1"]).first.subject.reference = "Patient/corrupted"

          assert_equal "Patient/1", @mock.patient_attributes(["1"]).first.subject.reference
        end

        # -- Attribute filter --

        def test_filters_to_requested_attributes
          @mock.seed_patient_attribute("1", "veteran-status", "veteran")
          @mock.seed_patient_attribute("1", "housing-status", "housed")
          @mock.seed_patient_attribute("1", "income-percent-fpl", 90)

          results = @mock.patient_attributes(["1"], attributes: %w[veteran-status income-percent-fpl])

          assert_equal %w[veteran-status income-percent-fpl].sort,
                       results.map { |o| o.code.coding.first.code }.sort
        end

        def test_attribute_filter_defaults_to_all
          @mock.seed_patient_attribute("1", "veteran-status", "veteran")
          @mock.seed_patient_attribute("1", "housing-status", "housed")

          assert_equal 2, @mock.patient_attributes(["1"]).length
        end

        def test_attribute_filter_rejects_unknown_codes
          assert_raises(ArgumentError) { @mock.patient_attributes(["1"], attributes: %w[shoe-size]) }
          # Visit-level code is unknown at patient level and vice versa.
          assert_raises(ArgumentError) { @mock.patient_attributes(["1"], attributes: %w[visit-service-category]) }
          assert_raises(ArgumentError) { @mock.visit_attributes(["1"], attributes: %w[veteran-status]) }
        end

        def test_visit_attribute_filter
          @mock.seed_visit_attribute("1", "enc-1", "visit-service-category", "medical")

          assert_equal 1, @mock.visit_attributes(["1"], attributes: %w[visit-service-category]).length
        end

        # -- Period semantics: current as of period end, latest-wins --

        def test_patient_read_returns_latest_value_as_of_period_end
          @mock.seed_patient_attribute("1", "sliding-fee-class", "class-a", effective: Date.new(2025, 2, 1))
          @mock.seed_patient_attribute("1", "sliding-fee-class", "class-b", effective: Date.new(2026, 2, 1))
          @mock.seed_patient_attribute("1", "sliding-fee-class", "class-c", effective: Date.new(2027, 2, 1))

          results = @mock.patient_attributes(["1"], period: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))

          # One value per attribute per patient: the latest effective on or
          # before period end — not values dated within the period.
          assert_equal ["class-b"], results.map { |o| o.valueCodeableConcept.coding.first.code }
        end

        def test_value_predating_period_is_still_current_as_of_period_end
          @mock.seed_patient_attribute("1", "sliding-fee-class", "class-a", effective: Date.new(2024, 6, 1))

          results = @mock.patient_attributes(["1"], period: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))

          assert_equal ["class-a"], results.map { |o| o.valueCodeableConcept.coding.first.code }
        end

        def test_period_end_is_inclusive
          @mock.seed_patient_attribute("1", "sliding-fee-class", "class-a", effective: Date.new(2025, 6, 1))
          @mock.seed_patient_attribute("1", "sliding-fee-class", "class-b", effective: Date.new(2026, 12, 31))

          results = @mock.patient_attributes(["1"], period: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))

          assert_equal ["class-b"], results.map { |o| o.valueCodeableConcept.coding.first.code }
        end

        def test_value_after_period_end_is_excluded
          @mock.seed_patient_attribute("1", "sliding-fee-class", "class-b", effective: Date.new(2027, 1, 1))

          assert_equal [], @mock.patient_attributes(["1"], period: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))
        end

        def test_latest_wins_is_per_attribute_and_per_patient
          @mock.seed_patient_attribute("1", "sliding-fee-class", "class-a", effective: Date.new(2025, 1, 1))
          @mock.seed_patient_attribute("1", "sliding-fee-class", "class-b", effective: Date.new(2026, 1, 1))
          @mock.seed_patient_attribute("1", "housing-status", "housed", effective: Date.new(2025, 1, 1))
          @mock.seed_patient_attribute("2", "sliding-fee-class", "class-c", effective: Date.new(2025, 1, 1))

          results = @mock.patient_attributes(%w[1 2], period: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))

          summary = results.map { |o| [o.subject.reference, o.code.coding.first.code, o.valueCodeableConcept.coding.first.code] }
          assert_includes summary, ["Patient/1", "sliding-fee-class", "class-b"]
          assert_includes summary, ["Patient/1", "housing-status", "housed"]
          assert_includes summary, ["Patient/2", "sliding-fee-class", "class-c"]
          assert_equal 3, results.length
        end

        def test_undated_attributes_are_currently_effective
          @mock.seed_patient_attribute("1", "agricultural-worker-status", "seasonal")

          results = @mock.patient_attributes(["1"], period: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))

          assert_equal ["seasonal"], results.map { |o| o.valueCodeableConcept.coding.first.code }
        end

        def test_visit_attributes_select_visits_within_period_inclusive
          @mock.seed_visit_attribute("1", "enc-1", "visit-service-category", "medical",
                                     effective: Date.new(2025, 12, 31))
          @mock.seed_visit_attribute("1", "enc-2", "visit-service-category", "dental",
                                     effective: Date.new(2026, 1, 1))
          @mock.seed_visit_attribute("1", "enc-3", "visit-service-category", "vision",
                                     effective: Date.new(2026, 12, 31))
          @mock.seed_visit_attribute("1", "enc-4", "visit-service-category", "other",
                                     effective: Date.new(2027, 1, 1))

          results = @mock.visit_attributes(["1"], period: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))

          assert_equal %w[Encounter/enc-2 Encounter/enc-3], results.map { |o| o.encounter.reference }
        end

        # -- Payer-category coverage --

        def test_coverage_normalizes_to_typed_fhir_coverage
          @mock.seed_patient_coverage("1", "medicaid")

          coverage = @mock.patient_coverages(["1"]).first

          assert_instance_of FHIR::Coverage, coverage
          coding = coverage.type.coding.first
          assert_equal PayerCategory::CODE_SYSTEM, coding.system
          assert_equal "medicaid", coding.code
          assert_equal "Patient/1", coverage.beneficiary.reference
          assert_equal "urn:lakeraven:source:site-a", coverage.meta.source
        end

        def test_coverage_rejects_unknown_payer_category
          assert_raises(ArgumentError) { @mock.seed_patient_coverage("1", "gold-plan") }
        end

        def test_coverage_latest_wins_as_of_period_end
          @mock.seed_patient_coverage("1", "uninsured", effective: Date.new(2025, 1, 1))
          @mock.seed_patient_coverage("1", "medicaid", effective: Date.new(2026, 6, 1))
          @mock.seed_patient_coverage("1", "medicare", effective: Date.new(2027, 1, 1))

          results = @mock.patient_coverages(["1"], period: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))

          assert_equal ["medicaid"], results.map { |c| c.type.coding.first.code }
        end

        def test_coverage_returns_copies
          @mock.seed_patient_coverage("1", "private")

          @mock.patient_coverages(["1"]).first.beneficiary.reference = "Patient/corrupted"

          assert_equal "Patient/1", @mock.patient_coverages(["1"]).first.beneficiary.reference
        end

        # -- Provenance --

        def test_tags_meta_source_from_descriptor
          @mock.seed_patient_attribute("1", "veteran-status", "non-veteran")
          @mock.seed_visit_attribute("1", "enc-1", "visit-service-category", "medical")
          @mock.seed_patient_coverage("1", "other-public")

          resources = @mock.patient_attributes(["1"]) + @mock.visit_attributes(["1"]) + @mock.patient_coverages(["1"])
          resources.each do |resource|
            assert_equal "urn:lakeraven:source:site-a", resource.meta.source
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

        def test_rejects_duplicate_source_ids_at_registration
          duplicate_id = lambda do
            DataReader::Mock.new(
              source_descriptor: SourceDescriptor.new(id: "site-a", ehr_platform: "rpms", channel: "supplemental")
            )
          end

          error = assert_raises(ArgumentError) do
            Lakeraven::Integrations.configure do |config|
              config.supplemental_data_readers = [duplicate_id.call, duplicate_id.call]
            end
          end
          assert_match(/duplicate supplemental source ids: site-a/, error.message)
        end

        def test_registered_readers_cannot_be_mutated_outside_configure
          Lakeraven::Integrations.configure { |c| c.supplemental_data_readers = [DataReader::Mock.new] }

          readers = Lakeraven::Integrations.supplemental_data_readers
          assert readers.frozen?
          assert_raises(FrozenError) { readers << DataReader::Mock.new }
          assert_equal 1, Lakeraven::Integrations.supplemental_data_readers.length
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
