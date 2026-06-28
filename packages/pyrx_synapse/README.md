# pyrx_synapse

Official Flutter SDK for the [PYRX Synapse](https://synapse.pyrx.tech)
customer communications platform — push notifications, identity, and
event tracking on iOS and Android.

Wraps the published native SDKs
([`PYRXSynapse 0.1.2+`](https://cocoapods.org/pods/PYRXSynapse) on
iOS,
[`tech.pyrx.synapse:synapse-core 0.1.4+`](https://central.sonatype.com/artifact/tech.pyrx.synapse/synapse-core)
and `:synapse-push 0.1.4+` on Android) and surfaces a single typed
Dart API plus a `Stream<PyrxEvent>` for push, identity, and queue
lifecycle events.

## Install

```yaml
dependencies:
  pyrx_synapse: ^0.1.0
```

```bash
flutter pub get
```

The umbrella package transitively pulls in
`pyrx_synapse_platform_interface`, `pyrx_synapse_ios`, and
`pyrx_synapse_android`. Flutter's federated-plugin resolver wires the
right implementation per platform — you do **not** add the platform
packages to your `pubspec.yaml` manually.

Then complete the per-platform configuration (Apple Developer +
APNs entitlement / Firebase project + `google-services.json`) per the
install guides linked from the [main README](https://github.com/PYRX-Tech/pyrx-synapse-flutter#install).

## Quickstart

```dart
import 'package:pyrx_synapse/pyrx_synapse.dart';

Future<void> main() async {
  await Synapse.initialize(const PyrxConfig(
    workspaceId: '<your-workspace-id>',
    apiKey: 'psk_test_<your-key>',
    environment: PyrxEnvironment.sandbox,
  ));

  // Subscribe to the merged event stream. Subscribe early so
  // cold-start push events (replayed from the native SDK's 4-event
  // buffer) reach this listener.
  Synapse.events.listen((event) {
    switch (event) {
      case PushReceived(:final event):
        debugPrint('foreground push: ${event.title}');
      case PushClicked(:final event):
        debugPrint('tap → deep link: ${event.deepLink}');
      case PushReceivedColdStart(:final event):
        debugPrint('cold start: ${event.title}');
      case QueueDrained(:final count):
        debugPrint('flushed $count events');
      case IdentityChanged(:final before, :final after):
        debugPrint('identity ${before?.externalId} → ${after.externalId}');
    }
  });

  await Synapse.identify('user_123', traits: {'plan': 'pro'});
  await Synapse.track('order_placed', properties: {'order_id': 'A-42'});
  await Synapse.requestPushPermission();
}
```

## What this package exposes

- `Synapse` static namespace — 12 imperative methods covering
  lifecycle, identity, events, push, and privacy. See
  [`docs/API.md`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/blob/main/docs/API.md).
- `Synapse.events` — broadcast `Stream<PyrxEvent>` carrying the
  5-event observer surface. See
  [`docs/STREAMS.md`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/blob/main/docs/STREAMS.md)
  for `StreamBuilder` / BLoC / Riverpod consumption patterns and
  [`docs/EVENTS.md`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/blob/main/docs/EVENTS.md)
  for the per-event payload reference.
- Sealed `PyrxAttributeValue` typed sum mirroring the native typed
  attribute value used in push payloads.

## Sample app

A fully working Flutter sample app at
[`examples/synapse_flutter_demo/`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/tree/main/examples/synapse_flutter_demo)
demonstrates every public surface — initialization, identify/alias/
logout, track/screen, requestPushPermission, registerForPushNotifications,
and a live observer view of the full merged `Stream<PyrxEvent>`.

## Docs

| Topic | Where |
|---|---|
| Install (iOS) | [`docs/INSTALL-IOS.md`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/blob/main/docs/INSTALL-IOS.md) |
| Install (Android) | [`docs/INSTALL-ANDROID.md`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/blob/main/docs/INSTALL-ANDROID.md) |
| Full API reference | [`docs/API.md`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/blob/main/docs/API.md) |
| Stream consumption patterns | [`docs/STREAMS.md`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/blob/main/docs/STREAMS.md) |
| Per-event payload reference | [`docs/EVENTS.md`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/blob/main/docs/EVENTS.md) |
| Migrating from a direct native integration | [`docs/MIGRATING-FROM-NATIVE.md`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/blob/main/docs/MIGRATING-FROM-NATIVE.md) |

## Toolchain floor

- Flutter `>= 3.24.0`
- Dart SDK `^3.6.0`
- iOS `13.0+` (`PYRXSynapse` raises to `14.0+` at `pod install`)
- Android `minSdk 24` (matches `synapse-core`)

## Repo + issues

The Flutter SDK ships from
[`PYRX-Tech/pyrx-synapse-flutter`](https://github.com/PYRX-Tech/pyrx-synapse-flutter).
File issues there.

## License

MIT — see [LICENSE](./LICENSE).
