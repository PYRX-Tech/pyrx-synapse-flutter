## 0.1.0 - 2026-06-28

First public release. iOS implementation of the PYRX Synapse Flutter
SDK federation. Bridges Dart calls to the published
[`PYRXSynapse 0.1.2+`](https://cocoapods.org/pods/PYRXSynapse) Swift
SDK from CocoaPods Trunk / SPM.

### What's here

- `PyrxSynapsePlugin.swift` — plugin registration. Auto-installs the
  `PyrxSynapsePlatform.instance` per Flutter's federated-plugin pattern
  + wires Pigeon HostApi + the 5 EventChannel handlers.
- `PyrxSynapseHostApiImpl.swift` — implements every method on the
  Pigeon-generated `PyrxSynapseHostApi`. Forwards to `Pyrx.shared.*`
  on the actor surface in `PYRXSynapse`.
- `PyrxEventStreamHandler.swift` — subscribes to
  `Pyrx.shared.events()` AsyncStream native-side; pushes envelopes
  back to Dart via the per-kind EventChannel.

### Toolchain floor

- iOS `13.0+` (transitively raised to `14.0+` by `PYRXSynapse`'s Podspec
  at `pod install` time)
- Xcode `15.0+` (matches PYRXSynapse's floor)
- Flutter `>= 3.24.0`, Dart `^3.6.0`

### Notes

Customers consume the umbrella `pyrx_synapse` package; this iOS
platform package resolves transitively per Flutter's federated-plugin
resolver.
