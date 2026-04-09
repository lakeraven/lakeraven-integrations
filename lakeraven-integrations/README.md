# lakeraven-integrations (core gem)

Adapter interface contracts for Lakeraven healthcare integrations, plus Mock implementations for development and testing.

This is the stable interface layer that engines like [`corvid`](https://github.com/lakeraven/corvid) and [`lakeraven-ehr`](https://github.com/lakeraven/lakeraven-ehr) depend on. Concrete backend implementations live in sibling gems in this monorepo (`lakeraven-rpms`, `lakeraven-fhir`, `lakeraven-directx12`) or in separate private gems.

## What's in here

### EDI interfaces (X12 transaction workflows)

- `Lakeraven::Integrations::Edi::Base` — abstract interface for `check_eligibility` (270/271), `submit_claim` (837), `check_claim_status` (276/277), `process_remittance` (835)
- `Lakeraven::Integrations::Edi::Mock` — canned responses for dev/test
- Response value objects: `EligibilityResponse`, `ClaimResponse`, `StatusResponse`, `RemittanceResponse`

### Planned (not yet extracted)

- Eligibility service layer (above the raw EDI interface)
- Claim submission orchestration
- Denial management interface
- Coding assist interface
- Dictation interface
- Imaging interface
- RoutingAdapter helpers for multi-adapter deployments

## Usage

Engines depend on this gem to get the interface contracts:

```ruby
# In corvid.gemspec or a SaaS shell's Gemfile
gem "lakeraven-integrations"
```

SaaS shells wire concrete adapter implementations at boot:

```ruby
# In corvid-saas/config/initializers/integrations.rb
require "lakeraven/integrations/edi/base"
require "lakeraven/integrations/edi/mock"

# For dev: use the mock
Lakeraven::Integrations.configure do |config|
  config.edi_adapter = Lakeraven::Integrations::Edi::Mock.new
end

# For production: wire a concrete adapter from a sibling gem or a private gem
# (see corvid-saas config for the real wiring)
```

## License

MIT
