## 0.1.0 - 2026-06-28

First public release. Android implementation of the PYRX Synapse
Flutter SDK federation. Bridges Dart calls to the published
[`tech.pyrx.synapse:synapse-core 0.1.4+`](https://central.sonatype.com/artifact/tech.pyrx.synapse/synapse-core)
and
[`:synapse-push 0.1.4+`](https://central.sonatype.com/artifact/tech.pyrx.synapse/synapse-push)
Kotlin SDKs from Maven Central.

### What's here

- `PyrxSynapsePlugin.kt` — plugin registration. Auto-installs the
  `PyrxSynapsePlatform.instance` per Flutter's federated-plugin pattern
  + wires Pigeon HostApi + the 5 EventChannel handlers + calls
  `PyrxPush.install(applicationContext)` from `synapse-push`.
- `PyrxSynapseHostApiImpl.kt` — implements every method on the
  Pigeon-generated `PyrxSynapseHostApi`. Forwards to `Pyrx.*` on the
  object surface in `synapse-core`.
- `PyrxEventStreamHandler.kt` — collects `Pyrx.events: SharedFlow<...>`
  native-side; pushes envelopes back to Dart via the per-kind
  EventChannel.

### Toolchain floor

- Android `minSdk 24` (transitively from `synapse-core`)
- Android `compileSdk 34`
- AGP `8.x`, Kotlin `1.9.x` (matches synapse-core)
- Java `17` for the Gradle build
- Flutter `>= 3.24.0`, Dart `^3.6.0`

### Notes

The `synapse-push` AAR's manifest auto-registers `PyrxMessagingService`
via Android's manifest merger — no consumer-side service declaration
needed.

Customers consume the umbrella `pyrx_synapse` package; this Android
platform package resolves transitively per Flutter's federated-plugin
resolver.
