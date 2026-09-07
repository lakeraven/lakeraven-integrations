# lakeraven-integrations (core gem)

Adapter interface contracts for Lakeraven healthcare integrations, plus Mock implementations for development and testing.

This is the stable interface layer that engines like [`corvid`](https://github.com/lakeraven/corvid) and [`lakeraven-ehr`](https://github.com/lakeraven/lakeraven-ehr) depend on. Concrete backend implementations live in sibling gems in this monorepo (`lakeraven-rpms`, `lakeraven-fhir`, `lakeraven-directx12`) or in separate private gems.

## What's in here

### EDI interfaces (X12 transaction workflows)

- `Lakeraven::Integrations::Edi::Base` — abstract interface for `check_eligibility` (270/271), `submit_claim` (837), `check_claim_status` (276/277), `process_remittance` (835)
- `Lakeraven::Integrations::Edi::Mock` — canned responses for dev/test
- Response value objects: `EligibilityResponse`, `ClaimResponse`, `StatusResponse`, `RemittanceResponse`

### Supplemental data interfaces (UDS reporting)

UDS reporting needs patient/visit-level attributes that vendor FHIR APIs do not expose — they live in each EHR's registration/eligibility/billing internals. Each EHR platform (RPMS first; Epic, NextGen, Greenway, eClinicalWorks planned) gets its own supplemental adapter behind one transport-agnostic interface.

- `Lakeraven::Integrations::Supplemental::Attributes` — the UDS supplemental attribute vocabulary (internal code system `urn:lakeraven:codesystem:uds-supplemental`): `income_percent_fpl`, `sliding_fee_class`, `payer_category`, `housing_status`, `agricultural_worker_status`, `veteran_status`, `language_barrier` (patient-level) and `visit_service_category` (visit-level). This vocabulary IS the contract adapters normalize into, so downstream SQL-on-FHIR sees one vocabulary regardless of source EHR.
- `Lakeraven::Integrations::Supplemental::DataReader::Base` — abstract read-only per-platform adapter interface: `patient_attributes` / `visit_attributes` for a patient/cohort + period, returning `FHIR::Observation` resources (fhir_models) coded from the Attributes vocabulary
- `Lakeraven::Integrations::Supplemental::SourceDescriptor` — value object identifying each source: `id`, `ehr_platform` (`rpms`, `epic`, `nextgen`, `greenway`, `ecw`, …), `channel` (`primary_fhir` | `supplemental`), `supplemental?`
- Returned resources carry `meta.source` set from the descriptor, so consumers keep per-resource source lineage (quality-measure certification/audit rules require supplemental data to be distinguishable by source)
- `Lakeraven::Integrations::Supplemental::DataReader::Mock` — seedable in-memory adapter for dev/test; its seed helpers build the normalized observation shape concrete adapters must emit
- Wired via `config.supplemental_data_readers` (an array — deployments can read supplemental data from several EHR platforms at once)

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
