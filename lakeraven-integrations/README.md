# lakeraven-integrations (core gem)

Adapter interface contracts for Lakeraven healthcare integrations, plus Mock implementations for development and testing.

This is the stable interface layer that engines like [`corvid`](https://github.com/lakeraven/corvid) and [`lakeraven-ehr`](https://github.com/lakeraven/lakeraven-ehr) depend on. Concrete backend implementations live in sibling gems in this monorepo (`lakeraven-rpms`, `lakeraven-fhir`, `lakeraven-x12`) or in separate private gems.

## What's in here

### EDI interfaces (X12 transaction workflows)

- `Lakeraven::Integrations::Edi::Base` — abstract interface for `check_eligibility` (270/271), `submit_claim` (837), `check_claim_status` (276/277), `process_remittance` (835)
- `Lakeraven::Integrations::Edi::Mock` — canned responses for dev/test
- Response value objects: `EligibilityResponse`, `ClaimResponse`, `StatusResponse`, `RemittanceResponse`

### Supplemental data interfaces (UDS reporting)

UDS reporting needs patient/visit-level attributes that vendor FHIR APIs do not expose — they live in each EHR's registration/eligibility/billing internals. Each EHR platform (RPMS first; Epic, NextGen, Greenway, eClinicalWorks planned) gets its own supplemental adapter behind one transport-agnostic interface.

- `Lakeraven::Integrations::Supplemental::Attributes` — the UDS supplemental attribute vocabulary (internal code system `https://terminology.lakeraven.com/CodeSystem/uds-supplemental-attribute`): `income-percent-fpl`, `sliding-fee-class`, `housing-status`, `agricultural-worker-status`, `veteran-status`, `language-barrier` (patient-level) and `visit-service-category` (visit-level). This vocabulary IS the contract adapters normalize into, so downstream SQL-on-FHIR sees one vocabulary regardless of source EHR.
- Attribute values: `income-percent-fpl` is a `valueQuantity` with the UCUM percent unit (`system: http://unitsofmeasure.org, code: %`), whole-percent semantics (138 = 138% FPL). Every other attribute is a `valueCodeableConcept` coded from `https://terminology.lakeraven.com/CodeSystem/uds-supplemental-value`, with a closed per-attribute enumeration held in `Attributes::DEFINITIONS[code][:values]` (e.g. housing-status: `housed | homeless-shelter | doubling-up | unsheltered | transitional | permanent-supportive | other | unknown`; visit-service-category keeps mental health and substance use as distinct codes — `medical | dental | mental-health | substance-use | vision | enabling | other` — because UDS Table 5 reports them on separate lines).
- Payer category is deliberately NOT an attribute Observation — it rides as `FHIR::Coverage` from `patient_coverages`, with `Coverage.type.coding` from `Lakeraven::Integrations::Supplemental::PayerCategory` (`https://terminology.lakeraven.com/CodeSystem/uds-payer-category`: `medicaid | medicare | private | uninsured | other-public`). `patient_coverages` returns ALL currently-effective coverages per patient — dual-eligibles carry Medicare AND Medicaid Coverages simultaneously (UDS Table 4 line 9a); temporal latest-wins applies per (beneficiary, payer category), never a collapse to one coverage per patient. "Currently effective" means status `active` and `period.start <= as-of <= period.end` (nil end = open-ended). Coverages carry the R4-required `payor` (synthetic display-only organization reference in the mock).
- `Lakeraven::Integrations::Supplemental::DataReader::Base` — abstract read-only per-platform adapter interface: `patient_attributes` / `visit_attributes` (with an optional `attributes:` subset filter) and `patient_coverages`, for a patient/cohort (`patient_ids` as a String or Array) + period. Period semantics: for patient-level registration-derived data, `period:` means "current as of period end" — the latest dated value effective on or before the period's (inclusive) end wins, and an UNDATED value beats all dated ones (it is the registration-current value); values dated after the as-of date never match, and `period: nil` means "current now" (as of today — future-dated values are excluded). At most one value per attribute per patient per read. Visit-level attributes select visits within the period. Callers batch large cohorts themselves; implementations define batch limits and either return complete results or raise — never silently skip patients.
- `Lakeraven::Integrations::Supplemental::SourceDescriptor` — value object identifying each source: `id`, `ehr_platform` (`rpms`, `epic`, `nextgen`, `greenway`, `ecw`, …), `channel` (`primary_fhir` | `supplemental`), `supplemental?`
- Returned resources carry `meta.source` set from the descriptor, so consumers keep per-resource source lineage (quality-measure certification/audit rules require supplemental data to be distinguishable by source)
- `Lakeraven::Integrations::Supplemental::DataReader::Mock` — seedable in-memory adapter for dev/test; its seed helpers (`seed_patient_attribute`, `seed_visit_attribute`, `seed_patient_coverage`) build — and enforce, rejecting unknown attributes/values — the normalized shape concrete adapters must emit, and reads return copies so callers can't corrupt the store
- Wired via `config.supplemental_data_readers` (an array — deployments can read supplemental data from several EHR platforms at once). Registration raises on duplicate source ids and on descriptors whose channel is not `supplemental` (a `primary_fhir` reader in this slot would stamp supplemental records with primary-feed lineage), and the public reader returns a frozen copy so global config can only change inside `configure`.

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
