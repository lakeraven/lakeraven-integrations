# lakeraven-fhir-models

FHIR R4 resource type definitions used by Lakeraven engines and integration adapters.

Each class is an ActiveModel value object representing a FHIR R4 resource, with typed attributes, validations, and `to_fhir` / `from_fhir` round-trip serialization.

## Included resources

- `Lakeraven::Fhir::Coverage` — FHIR Coverage
- `Lakeraven::Fhir::CoverageEligibilityRequest` — FHIR CoverageEligibilityRequest
- `Lakeraven::Fhir::CoverageEligibilityResponse` — FHIR CoverageEligibilityResponse

More resources (`Claim`, `ClaimResponse`, `ExplanationOfBenefit`, etc.) will be added as the interface needs them.

## Usage

```ruby
require "lakeraven/fhir"

request = Lakeraven::Fhir::CoverageEligibilityRequest.new(
  patient_dfn: "12345",
  coverage_type: "medicaid",
  service_date: Date.today
)

fhir_hash = request.to_fhir
# => { resourceType: "CoverageEligibilityRequest", ... }

reconstructed = Lakeraven::Fhir::CoverageEligibilityRequest.from_fhir(fhir_hash)
```

## Dependencies

- `activemodel ~> 7.1` (for typed attributes and validations)
- Ruby `>= 3.4.0`

## License

MIT
