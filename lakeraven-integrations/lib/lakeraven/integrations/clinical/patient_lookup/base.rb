# frozen_string_literal: true

module Lakeraven
  module Integrations
    module Clinical
      module PatientLookup
        # Abstract patient lookup interface.
        #
        # Concrete adapters (RPC, FHIR, mock) implement these methods.
        # Engines call through this interface; they never know the backend.
        #
        # All methods return plain hashes with symbol keys, not model instances.
        # The consuming engine wraps them in its own domain objects.
        class Base
          # @param dfn [Integer] patient DFN / internal ID
          # @return [Hash, nil] patient attributes or nil if not found
          def find(dfn)
            raise NotImplementedError, "#{self.class}#find not implemented"
          end

          # @param name_pattern [String] name prefix to search
          # @return [Array<Hash>] matching patient attribute hashes
          def search(name_pattern)
            raise NotImplementedError, "#{self.class}#search not implemented"
          end

          # @param ssn [String] social security number
          # @return [Hash, nil] patient attributes or nil if not found
          def find_by_ssn(ssn)
            raise NotImplementedError, "#{self.class}#find_by_ssn not implemented"
          end
        end
      end
    end
  end
end
