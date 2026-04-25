# frozen_string_literal: true

module Lakeraven
  module Integrations
    module Clinical
      module ClinicalDataReader
        # In-memory mock for testing without a backend.
        class Mock < Base
          def initialize
            @data = {} # { dfn => { resource_type => [hashes] } }
          end

          # Seed clinical data for testing.
          # @param dfn [Integer] patient DFN
          # @param resource_type [String] FHIR resource type
          # @param records [Array<Hash>] attribute hashes (must include :ien)
          def seed(dfn, resource_type, records)
            @data[dfn] ||= {}
            @data[dfn][resource_type] = records
          end

          def for_patient(dfn, resource_type:)
            @data.dig(dfn, resource_type) || []
          end

          def find(resource_type, ien)
            @data.each_value do |types|
              records = types[resource_type] || []
              found = records.find { |r| r[:ien].to_s == ien.to_s }
              return found if found
            end
            nil
          end
        end
      end
    end
  end
end
