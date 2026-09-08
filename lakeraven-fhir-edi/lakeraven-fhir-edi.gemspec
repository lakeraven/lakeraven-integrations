# frozen_string_literal: true

require_relative "lib/lakeraven/fhir/version"

Gem::Specification.new do |spec|
  spec.name        = "lakeraven-fhir-edi"
  spec.version     = Lakeraven::Fhir::VERSION
  spec.authors     = ["Lakeraven"]
  spec.email       = ["eng@lakeraven.com"]
  spec.homepage    = "https://github.com/lakeraven/lakeraven-integrations"
  spec.summary     = "FHIR R4 decorators carrying EDI/PRC transaction semantics for Lakeraven integrations"
  spec.description = "Ruby value objects decorating FHIR R4 financial-module resources " \
                     "(Coverage, CoverageEligibilityRequest/Response, Claim, ClaimResponse, " \
                     "ExplanationOfBenefit) with the EDI and PRC transaction semantics " \
                     "Lakeraven engines and integration adapters need: PRC coverage statuses, " \
                     "837 accessors, eligibility side-attributes. Uses ActiveModel for typed " \
                     "attributes and validations; each class supports to_fhir / from_fhir " \
                     "round-trip. Note: the gem is named lakeraven-fhir-edi but is required " \
                     "as lakeraven/fhir and defines the Lakeraven::Fhir::* namespace."
  spec.license     = "MIT"
  spec.metadata    = {
    "homepage_uri"      => "https://github.com/lakeraven/lakeraven-integrations",
    "source_code_uri"   => "https://github.com/lakeraven/lakeraven-integrations/tree/main/lakeraven-fhir-edi"
  }

  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "README.md"]
  end

  spec.require_paths = ["lib"]

  spec.add_dependency "activemodel", ">= 7.1"
  spec.add_dependency "fhir_models", "~> 4.3"
end
