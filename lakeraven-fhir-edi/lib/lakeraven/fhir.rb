# frozen_string_literal: true

require "active_model"
require "date"
require "securerandom"
require "time"

require_relative "fhir/version"
require_relative "fhir/coverage"
require_relative "fhir/coverage_eligibility_request"
require_relative "fhir/coverage_eligibility_response"
require_relative "fhir/claim"
require_relative "fhir/claim_response"
require_relative "fhir/explanation_of_benefit"

module Lakeraven
  # FHIR R4 resource type definitions for Lakeraven integrations.
  #
  # Each class is an ActiveModel value object representing a FHIR R4 resource,
  # with typed attributes, validations, and to_fhir / from_fhir round-trip
  # serialization. Used by Lakeraven engines (corvid, lakeraven-ehr) and by
  # integration adapters (lakeraven-x12, other clearinghouse adapters, future gems)
  # as the canonical shared vocabulary for healthcare data.
  module Fhir
  end
end
