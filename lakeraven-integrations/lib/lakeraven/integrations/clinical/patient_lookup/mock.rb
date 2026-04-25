# frozen_string_literal: true

module Lakeraven
  module Integrations
    module Clinical
      module PatientLookup
        # In-memory mock for testing without a backend.
        class Mock < Base
          def initialize
            @patients = {}
          end

          # Seed a patient for testing.
          # @param attrs [Hash] must include :dfn and :name; optionally :ssn and others
          def seed(**attrs)
            @patients[attrs[:dfn]] = attrs
          end

          def find(dfn)
            @patients[dfn]
          end

          def search(name_pattern)
            return @patients.values if name_pattern.to_s.empty?

            prefix = name_pattern.to_s.upcase
            @patients.values.select { |p| p[:name].to_s.upcase.start_with?(prefix) }
          end

          def find_by_ssn(ssn)
            @patients.values.find { |p| p[:ssn] == ssn }
          end
        end
      end
    end
  end
end
