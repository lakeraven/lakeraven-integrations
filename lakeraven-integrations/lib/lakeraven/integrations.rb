# frozen_string_literal: true

require_relative "integrations/version"
require_relative "integrations/edi/base"
require_relative "integrations/edi/mock"

module Lakeraven
  # Lakeraven::Integrations is the interface-contract layer between Lakeraven
  # engines (corvid, lakeraven-ehr) and concrete backend implementations.
  #
  # Engines depend only on this gem and its interface modules. Concrete adapters
  # (wrapping RPMS, FHIR, commercial clearinghouses, OSS projects, etc.) live in
  # sibling gems in the lakeraven-integrations monorepo (for public concretes)
  # or in the private lakeraven-private monorepo (for private concretes).
  #
  # SaaS shells (corvid-saas, lakeraven-ehr-saas) are the composition layer —
  # they bundle engines + concrete adapter gems and wire the adapters into the
  # interface slots at boot time.
  module Integrations
  end
end
