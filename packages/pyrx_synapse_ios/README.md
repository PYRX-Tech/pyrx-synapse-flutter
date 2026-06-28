# pyrx_synapse_ios

iOS implementation of the PYRX Synapse Flutter SDK.

> **Do not depend on this package directly.** App-facing consumers should
> depend on `pyrx_synapse`; the federated plugin resolver will pick this
> package up automatically on iOS builds.

This package contains:

- `ios/pyrx_synapse_ios.podspec` — declares the `PYRXSynapse >= 0.1.2`
  CocoaPods dependency that ships the underlying Swift SDK.
- `ios/Classes/PyrxSynapsePlugin.swift` — the `FlutterPlugin` entry point.
  Registers the Pigeon-generated `PyrxSynapseHostApi` handler and wires the
  five Pigeon `EventChannelApi` sinks against
  `PYRXSynapse.Pyrx.shared.events()` (the AsyncStream observer surface added
  in Phase 9.2.1 / PYRXSynapse 0.1.2).
- `lib/pyrx_synapse_ios.dart` — Dart-side `PyrxSynapsePlatform` subclass
  that platform-interface auto-instantiates when running on iOS.
