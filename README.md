# lakeraven-integrations

Public Rails-style monorepo containing Lakeraven's integration interfaces and public concrete adapter gems. Part of the Lakeraven healthcare platform.

## Structure

Each subdirectory is an independent gem published from this monorepo:

- **`lakeraven-integrations/`** — core gem. Adapter interface contracts (Billing, Eligibility, EDI, Denial, Coding, Dictation, Imaging, etc.) plus Mock implementations for dev/test. The stable contract that engines (`corvid`, `lakeraven-ehr`) depend on.
- **`lakeraven-rpms/`** — public concrete adapter wrapping RPMS admin packages (TPB, eligibility, patient registration, insurer file, etc.) via [`rpms-rpc`](https://github.com/lakeraven/rpms-rpc). (planned — not yet extracted)
- **`lakeraven-fhir/`** — public concrete adapter for generic FHIR R4 endpoints. (planned — not yet extracted)
- **`lakeraven-directx12/`** — public concrete adapter for raw X12 over SFTP/AS2/HTTPS (the vendor-lock hedge).

## Design principles

- **Engines depend on interfaces, not implementations.** `corvid` and `lakeraven-ehr` depend only on the `lakeraven-integrations` core gem. SaaS shells wire concrete adapters at boot.
- **One gem per backend.** Each concrete adapter gem wraps one backend (RPMS, FHIR, raw X12, etc.) and implements whatever interfaces that backend supports.
- **Public/private boundary by repo visibility.** Public concrete adapters (wrapping FOIA code, generic protocols, or anything Lakeraven is happy to advertise) live here. Private concrete adapters (wrapping commercial vendors or OSS dependencies Lakeraven wants to hide) live in the private `lakeraven-private` monorepo.
- **Rails-style monorepo.** Each gem is a self-contained gemspec subdirectory with its own `lib/`, `test/`, and `.gemspec`, but they share root-level tooling (Gemfile, Rakefile, CI).

## Development

```
bundle install
cd lakeraven-integrations && bundle exec rake test
cd lakeraven-directx12 && bundle exec rake test
```

## License

MIT
