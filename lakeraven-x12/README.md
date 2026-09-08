# lakeraven-x12

Raw X12 EDI adapter for Lakeraven integrations. Implements `Lakeraven::Integrations::Edi::Base` by generating X12 envelopes and submitting them via configurable transport (HTTPS, SFTP, AS2).

This is the **public vendor-lock hedge**: any Lakeraven customer can self-host the entire public stack (corvid + lakeraven-integrations + lakeraven-x12) and bring their own clearinghouse trading-partner contract. No dependency on any commercial clearinghouse vendor or private adapter gem.

## Usage

```ruby
require "lakeraven/x12"

adapter = Lakeraven::X12::Adapter.new(
  endpoint: "https://clearinghouse.example.com/edi",
  sender_id: "LAKERAVEN",
  receiver_id: "PAYER01",
  transport: :https,
  credentials: { username: ENV["EDI_USER"], password: ENV["EDI_PASS"] }
)

response = adapter.check_eligibility("P12345", "1234567890", ["30"])
```

## Caveats

This is a generic implementation. Production deployments that need:
- Full X12 envelope validation (segment counts, control number management, ack handling)
- SFTP or AS2 transport (only HTTPS is implemented in v0.1)
- Trading-partner-specific quirks

should either extend this adapter or use a commercial clearinghouse adapter from the private `lakeraven-private` monorepo.

## License

MIT
