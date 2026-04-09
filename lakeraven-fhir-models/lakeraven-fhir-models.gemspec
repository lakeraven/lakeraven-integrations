# frozen_string_literal: true

require_relative "lib/lakeraven/fhir/version"

Gem::Specification.new do |spec|
  spec.name        = "lakeraven-fhir-models"
  spec.version     = Lakeraven::Fhir::VERSION
  spec.authors     = ["Lakeraven"]
  spec.email       = ["eng@lakeraven.com"]
  spec.homepage    = "https://github.com/lakeraven/lakeraven-integrations"
  spec.summary     = "FHIR R4 resource type definitions for Lakeraven integrations"
  spec.description = "Ruby value objects representing FHIR R4 resources used by " \
                     "Lakeraven engines and integration adapters. Includes Coverage, " \
                     "CoverageEligibilityRequest, CoverageEligibilityResponse, and other " \
                     "financial-module resources. Uses ActiveModel for typed attributes " \
                     "and validations. Each class supports to_fhir / from_fhir round-trip."
  spec.license     = "MIT"
  spec.metadata    = {
    "homepage_uri"      => "https://github.com/lakeraven/lakeraven-integrations",
    "source_code_uri"   => "https://github.com/lakeraven/lakeraven-integrations/tree/main/lakeraven-fhir-models"
  }

  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "README.md"]
  end

  spec.require_paths = ["lib"]

  spec.add_dependency "activemodel", "~> 7.1"
  spec.add_dependency "fhir_models", "~> 4.3"
end
