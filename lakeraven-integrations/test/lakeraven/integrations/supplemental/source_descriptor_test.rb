# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Integrations
    module Supplemental
      class SourceDescriptorTest < Minitest::Test
        def test_exposes_id_platform_and_channel
          descriptor = SourceDescriptor.new(id: "site-a", ehr_platform: "rpms", channel: "supplemental")

          assert_equal "site-a", descriptor.id
          assert_equal "rpms", descriptor.ehr_platform
          assert_equal "supplemental", descriptor.channel
        end

        def test_known_ehr_platforms
          assert_equal %w[rpms epic nextgen greenway ecw], SourceDescriptor::KNOWN_EHR_PLATFORMS
        end

        def test_channel_vocabulary
          assert_equal %w[primary_fhir supplemental], SourceDescriptor::CHANNELS
        end

        def test_accepts_symbols
          descriptor = SourceDescriptor.new(id: "site-a", ehr_platform: :epic, channel: :primary_fhir)

          assert_equal "epic", descriptor.ehr_platform
          assert_equal "primary_fhir", descriptor.channel
        end

        def test_supplemental_channel_is_supplemental
          assert SourceDescriptor.new(id: "s", ehr_platform: "nextgen", channel: "supplemental").supplemental?
          refute SourceDescriptor.new(id: "s", ehr_platform: "nextgen", channel: "primary_fhir").supplemental?
        end

        def test_accepts_unlisted_platform_tokens
          descriptor = SourceDescriptor.new(id: "s", ehr_platform: "future_ehr", channel: "supplemental")
          assert_equal "future_ehr", descriptor.ehr_platform
        end

        def test_rejects_malformed_platform
          error = assert_raises(ArgumentError) do
            SourceDescriptor.new(id: "s", ehr_platform: "Not An EHR", channel: "supplemental")
          end
          assert_match(/lowercase token/, error.message)
        end

        def test_rejects_unknown_channel
          error = assert_raises(ArgumentError) do
            SourceDescriptor.new(id: "s", ehr_platform: "rpms", channel: "sidecar")
          end
          assert_match(/channel must be one of/, error.message)
        end

        def test_rejects_blank_id
          assert_raises(ArgumentError) { SourceDescriptor.new(id: "", ehr_platform: "rpms", channel: "supplemental") }
          assert_raises(ArgumentError) { SourceDescriptor.new(id: nil, ehr_platform: "rpms", channel: "supplemental") }
        end

        def test_uri_embeds_source_id
          descriptor = SourceDescriptor.new(id: "site-a", ehr_platform: "rpms", channel: "supplemental")
          assert_equal "urn:lakeraven:source:site-a", descriptor.uri
        end

        def test_value_equality
          a = SourceDescriptor.new(id: "s", ehr_platform: "epic", channel: "supplemental")
          b = SourceDescriptor.new(id: "s", ehr_platform: "epic", channel: "supplemental")
          c = SourceDescriptor.new(id: "s", ehr_platform: "epic", channel: "primary_fhir")

          assert_equal a, b
          assert_equal a.hash, b.hash
          refute_equal a, c
        end

        def test_frozen
          assert SourceDescriptor.new(id: "s", ehr_platform: "ecw", channel: "supplemental").frozen?
        end
      end
    end
  end
end
