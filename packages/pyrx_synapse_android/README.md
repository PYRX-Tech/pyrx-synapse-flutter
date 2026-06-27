# pyrx_synapse_android

Android implementation of the PYRX Synapse Flutter SDK.

> **Do not depend on this package directly.** App-facing consumers should
> depend on `pyrx_synapse`; the federated plugin resolver will pick this
> package up automatically on Android builds.

This package contains:

- `android/build.gradle` — declares the `tech.pyrx.synapse:synapse-core` +
  `synapse-push` Maven Central dependencies (>= 0.1.4) that ship the
  underlying Kotlin SDKs.
- `android/src/main/kotlin/tech/pyrx/synapse/flutter/PyrxSynapsePlugin.kt` —
  the `FlutterPlugin` entry point. Registers the Pigeon-generated
  `PyrxSynapseHostApi` handler and wires the five Pigeon `EventChannelApi`
  sinks against `Pyrx.events` (the SharedFlow observer surface added in
  Phase 9.2.1 / synapse-core 0.1.4).
- `lib/pyrx_synapse_android.dart` — Dart-side `PyrxSynapsePlatform` subclass
  that platform-interface auto-instantiates when running on Android.

## Build requirements

- JDK 17 (`JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.0.2.jdk/Contents/Home`)
- `minSdkVersion 24`, `compileSdkVersion 34`
