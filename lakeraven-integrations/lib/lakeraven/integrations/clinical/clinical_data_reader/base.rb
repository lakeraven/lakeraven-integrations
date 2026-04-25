# frozen_string_literal: true

module Lakeraven
  module Integrations
    module Clinical
      module ClinicalDataReader
        # Abstract clinical data reader interface.
        #
        # Provides read access to clinical resources (allergies, conditions,
        # medications, observations, etc.) by patient.
        #
        # All methods return plain hashes with symbol keys.
        class Base
          # @param dfn [Integer] patient DFN
          # @param resource_type [String] FHIR resource type name
          # @return [Array<Hash>] clinical data attribute hashes
          def for_patient(dfn, resource_type:)
            raise NotImplementedError, "#{self.class}#for_patient not implemented"
          end

          # @param resource_type [String] FHIR resource type name
          # @param ien [String] resource internal ID
          # @return [Hash, nil] single resource attributes or nil
          def find(resource_type, ien)
            raise NotImplementedError, "#{self.class}#find not implemented"
          end
        end
      end
    end
  end
end
