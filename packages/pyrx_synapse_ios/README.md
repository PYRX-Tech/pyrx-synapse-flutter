# pyrx_synapse_ios

iOS implementation of the [`pyrx_synapse`](https://pub.dev/packages/pyrx_synapse)
Flutter SDK. Bridges Dart calls to the published
[`PYRXSynapse 0.1.2+`](https://cocoapods.org/pods/PYRXSynapse) Swift
SDK from CocoaPods Trunk / SPM.

**You do not depend on this package directly.** Add the umbrella
`pyrx_synapse` package to your `pubspec.yaml` and Flutter's
federated-plugin resolver picks this package up on iOS builds.

## What this package contains

- `ios/pyrx_synapse_ios.podspec` — declares the `PYRXSynapse >= 0.1.2`
  CocoaPods dependency that ships the underlying Swift SDK.
- `ios/Classes/PyrxSynapsePlugin.swift` — the `FlutterPlugin` entry
  point. Registers the Pigeon-generated `PyrxSynapseHostApi` handler
  and wires the five Pigeon `EventChannelApi` sinks against
  `PYRXSynapse.Pyrx.shared.events()` (the AsyncStream observer
  surface added in Phase 9.2.1 / `PYRXSynapse 0.1.2`).
- `ios/Classes/PyrxSynapseHostApiImpl.swift` — the actual host-API
  body. Forwards every method 1:1 to `Pyrx.shared.*`.
- `ios/Classes/PyrxEventStreamHandler.swift` — handles the
  EventChannel stream lifecycle (listen / cancel) + `AsyncStream` →
  `FlutterEventSink` plumbing.
- `lib/pyrx_synapse_ios.dart` — Dart-side `PyrxSynapsePlatform`
  subclass that the platform-interface package auto-instantiates when
  running on iOS.

## Toolchain floor

- iOS `13.0+` (transitively raised to `14.0+` by `PYRXSynapse`'s
  Podspec at `pod install` time)
- Xcode `15.0+`
- Flutter `>= 3.24.0`, Dart `^3.6.0`

## App-side install steps you may still need

The plugin's `register(with:)` runs automatically at app launch — the
native APNs callbacks (`didRegisterForRemoteNotificationsWithDeviceToken`,
foreground/background/click delegate methods) are intercepted via
`FlutterAppDelegate`'s plugin chain, so the default case requires zero
glue in `AppDelegate.swift`.

If your app extends a non-`FlutterAppDelegate` parent class or you
need to integrate with another push SDK, see
[`docs/INSTALL-IOS.md`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/blob/main/docs/INSTALL-IOS.md)
for the manual-forwarding pattern.

## Repo + issues

The Flutter SDK ships from
[`PYRX-Tech/pyrx-synapse-flutter`](https://github.com/PYRX-Tech/pyrx-synapse-flutter).
File issues there.

## License

MIT — see [LICENSE](./LICENSE).
