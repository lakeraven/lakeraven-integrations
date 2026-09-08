# lakeraven-fhir-edi

FHIR R4 decorators carrying EDI/PRC transaction semantics, used by Lakeraven engines and integration adapters: PRC coverage statuses, 837 accessors, eligibility side-attributes on top of the standard FHIR R4 financial-module resources.

Each class is an ActiveModel value object decorating a FHIR R4 resource, with typed attributes, validations, and `to_fhir` / `from_fhir` round-trip serialization.

Note: the gem is named `lakeraven-fhir-edi`, but it is required as `lakeraven/fhir` and defines the `Lakeraven::Fhir::*` namespace.

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
