# frozen_string_literal: true

module Lakeraven
  module Integrations
    module Supplemental
      # Immutable value object identifying a data source feeding quality-measure
      # evaluation: which EHR platform it reads, and through which channel —
      # the platform's primary FHIR API, or the supplemental path into its
      # non-FHIR registration/eligibility/billing internals.
      #
      # Every DataReader implementation exposes one so downstream consumers
      # (population-health engines) can keep per-resource source lineage —
      # quality-measure certification and audit rules require supplemental data
      # to be distinguishable from the primary FHIR feed, by source.
      class SourceDescriptor
        # EHR platforms with planned supplemental adapters. Not a closed set —
        # any lowercase token is accepted so new platforms don't require a
        # vocabulary release.
        KNOWN_EHR_PLATFORMS = %w[rpms epic nextgen greenway ecw].freeze

        CHANNELS = %w[primary_fhir supplemental].freeze

        attr_reader :id, :ehr_platform, :channel

        # @param id [String] stable identifier for the source (unique per deployment)
        # @param ehr_platform [String, Symbol] platform token (see KNOWN_EHR_PLATFORMS)
        # @param channel [String, Symbol] one of CHANNELS
        def initialize(id:, ehr_platform:, channel:)
          raise ArgumentError, "id must be a non-empty string" if id.to_s.strip.empty?

          ehr_platform = ehr_platform.to_s
          unless ehr_platform.match?(/\A[a-z][a-z0-9_]*\z/)
            raise ArgumentError, "ehr_platform must be a lowercase token (got #{ehr_platform.inspect})"
          end

          channel = channel.to_s
          unless CHANNELS.include?(channel)
            raise ArgumentError, "channel must be one of: #{CHANNELS.join(', ')} (got #{channel.inspect})"
          end

          @id = id.to_s
          @ehr_platform = ehr_platform
          @channel = channel
          freeze
        end

        # @return [Boolean] true when this source is the supplemental channel
        def supplemental?
          channel == "supplemental"
        end

        # URI form stamped into +meta.source+ on resources returned by the
        # source's reader, so lineage survives on the resource itself.
        # @return [String]
        def uri
          "urn:lakeraven:source:#{id}"
        end

        def ==(other)
          other.is_a?(SourceDescriptor) &&
            other.id == id &&
            other.ehr_platform == ehr_platform &&
            other.channel == channel
        end
        alias eql? ==

        def hash
          [self.class, id, ehr_platform, channel].hash
        end
      end
    end
  end
end
