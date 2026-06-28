## 0.1.0 - 2026-06-28

First public release. Defines the platform-interface contract every
`pyrx_synapse_*` platform implementation extends, plus the Pigeon spec
that codegens the type-safe MethodChannel + EventChannel layer between
Dart and the iOS / Android native SDKs.

### What's here

- `PyrxSynapsePlatform` — abstract base class. Platform packages
  override and register an instance via
  `PyrxSynapsePlatform.instance = MyImpl()` in their `registerWith()`.
- `MethodChannelPyrxSynapse` — default implementation. Routes every
  call through the Pigeon-generated `PyrxSynapseHostApi` over the
  standard Flutter platform channel.
- Pigeon spec at `pigeons/pyrx_synapse_messages.dart` — single source
  of truth for the Dart ↔ native wire shape:
  - `PyrxSynapseHostApi` (HostApi) — 12 method calls
  - `PyrxEventEnvelope` (sealed DTO) + per-kind EventChannel APIs for
    the 5-event observer surface
- Generated outputs committed to `lib/src/generated/`,
  `ios/Classes/generated/`, and `android/.../generated/`. Re-generate
  via `melos run pigeon-generate` after editing the spec.

### Toolchain floor

- Flutter `>= 3.24.0`
- Dart SDK `^3.6.0`

### Notes

Customers integrate the umbrella `pyrx_synapse` package — this
platform-interface package is a transitive dependency. Direct
consumption is supported but unusual (e.g., implementing a custom
platform package for `pyrx_synapse_web` or `pyrx_synapse_macos`).
