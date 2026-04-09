# frozen_string_literal: true

require_relative "lib/lakeraven/integrations/version"

Gem::Specification.new do |spec|
  spec.name        = "lakeraven-integrations"
  spec.version     = Lakeraven::Integrations::VERSION
  spec.authors     = ["Lakeraven"]
  spec.email       = ["eng@lakeraven.com"]
  spec.homepage    = "https://github.com/lakeraven/lakeraven-integrations"
  spec.summary     = "Adapter interface contracts for Lakeraven healthcare integrations"
  spec.description = "The stable interface layer that engines like corvid and lakeraven-ehr " \
                     "depend on. Provides adapter contracts for EDI (billing, eligibility, " \
                     "claim status, remittance), denial management, coding, dictation, imaging, " \
                     "and other healthcare integration categories, plus Mock implementations " \
                     "for dev/test. Concrete backend implementations live in sibling gems " \
                     "(lakeraven-rpms, lakeraven-fhir, lakeraven-directx12) or private gems."
  spec.license     = "MIT"
  spec.metadata    = {
    "homepage_uri"      => "https://github.com/lakeraven/lakeraven-integrations",
    "source_code_uri"   => "https://github.com/lakeraven/lakeraven-integrations/tree/main/lakeraven-integrations",
    "changelog_uri"     => "https://github.com/lakeraven/lakeraven-integrations/blob/main/lakeraven-integrations/CHANGELOG.md"
  }

  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "README.md"]
  end

  spec.require_paths = ["lib"]

  # Core gem is deliberately Rails-free and dependency-free. Money fields
  # use integer cents throughout, so no BigDecimal dependency is required.
end
