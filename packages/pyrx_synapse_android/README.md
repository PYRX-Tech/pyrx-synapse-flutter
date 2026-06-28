# pyrx_synapse_android

Android implementation of the [`pyrx_synapse`](https://pub.dev/packages/pyrx_synapse)
Flutter SDK. Bridges Dart calls to the published
[`tech.pyrx.synapse:synapse-core 0.1.4+`](https://central.sonatype.com/artifact/tech.pyrx.synapse/synapse-core)
and
[`:synapse-push 0.1.4+`](https://central.sonatype.com/artifact/tech.pyrx.synapse/synapse-push)
Kotlin SDKs from Maven Central.

**You do not depend on this package directly.** Add the umbrella
`pyrx_synapse` package to your `pubspec.yaml` and Flutter's
federated-plugin resolver picks this package up on Android builds.

## What this package contains

- `android/build.gradle` — declares the
  `tech.pyrx.synapse:synapse-core` + `synapse-push` Maven Central
  dependencies (>= 0.1.4) that ship the underlying Kotlin SDKs.
- `android/src/main/kotlin/.../PyrxSynapsePlugin.kt` — the
  `FlutterPlugin` entry point. Registers the Pigeon-generated
  `PyrxSynapseHostApi` handler, wires the five Pigeon
  `EventChannelApi` sinks against `Pyrx.events: SharedFlow<...>`, and
  calls `PyrxPush.install(applicationContext)` from `synapse-push` so
  FCM registration happens automatically.
- `android/src/main/kotlin/.../PyrxSynapseHostApiImpl.kt` — the
  actual host-API body. Forwards every method 1:1 to `Pyrx.*` and
  `PyrxPush.*`.
- `android/src/main/kotlin/.../PyrxEventStreamHandler.kt` — handles
  the EventChannel stream lifecycle (listen / cancel) + `SharedFlow` →
  `EventChannel.EventSink` plumbing.
- `lib/pyrx_synapse_android.dart` — Dart-side `PyrxSynapsePlatform`
  subclass that the platform-interface package auto-instantiates when
  running on Android.

## Toolchain floor

- Android `minSdk 24` (transitively from `synapse-core`)
- Android `compileSdk 34`
- AGP `8.x`, Kotlin `1.9.x` (matches synapse-core)
- JDK 17 for the Gradle build
  (`JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.x.x.jdk/Contents/Home`
  on macOS — set it before running `flutter build apk` if your
  system Java is not 17)
- Flutter `>= 3.24.0`, Dart `^3.6.0`

## App-side install steps you may still need

The plugin's `onAttachedToEngine` runs automatically at app launch —
`PyrxPush.install(applicationContext)` registers `PyrxMessagingService`
via Android's manifest merger (the `synapse-push` AAR ships the
service declaration), so the default case requires zero glue in
`AndroidManifest.xml`.

You DO need to:

- Drop a `google-services.json` from your Firebase project into
  `android/app/`.
- Add `POST_NOTIFICATIONS` to your `AndroidManifest.xml` if you target
  Android 13+ (API 33).

See
[`docs/INSTALL-ANDROID.md`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/blob/main/docs/INSTALL-ANDROID.md)
for the full walkthrough.

## Repo + issues

The Flutter SDK ships from
[`PYRX-Tech/pyrx-synapse-flutter`](https://github.com/PYRX-Tech/pyrx-synapse-flutter).
File issues there.

## License

MIT — see [LICENSE](./LICENSE).
