# `pyrx_synapse`

Official Flutter SDK for the [PYRX Synapse](https://synapse.pyrx.tech)
customer communications platform. Events, identity, push notifications,
and privacy controls — for iOS and Android, with a single typed Dart
API plus a `Stream<PyrxEvent>` observer surface.

This package is a **thin federated wrapper** around the published
native SDKs:

- iOS: [`PYRXSynapse 0.1.2+`](https://cocoapods.org/pods/PYRXSynapse)
  (CocoaPods Trunk + Swift Package Manager)
- Android:
  [`tech.pyrx.synapse:synapse-core 0.1.4+`](https://central.sonatype.com/artifact/tech.pyrx.synapse/synapse-core)
  +
  [`tech.pyrx.synapse:synapse-push 0.1.4+`](https://central.sonatype.com/artifact/tech.pyrx.synapse/synapse-push)
  (Maven Central)

The Flutter package owns the Dart bridge, the typed event sealed-class
hierarchy, the documentation, and the federated plugin structure. The
event queue, network layer, identity manager, privacy cascade, and
push registration all live in the native SDKs — so the Flutter package
inherits every native-SDK bug fix and tuning automatically.

| Concern | Where it lives |
|---|---|
| Public Dart API | `pyrx_synapse` (this package) |
| Pigeon spec + platform contract | `pyrx_synapse_platform_interface` |
| iOS Swift bridge | `pyrx_synapse_ios` |
| Android Kotlin bridge | `pyrx_synapse_android` |
| iOS native code (queue, network, push) | `PYRXSynapse` Pod |
| Android native code (queue, network, push) | `tech.pyrx.synapse:synapse-*` AARs |
| Backend (events, push delivery) | `synapse-events.pyrx.tech` |

---

## Supported platforms

- **Flutter** `>= 3.24.0` (Dart SDK `^3.6.0`)
- **iOS** `13.0+` (transitively raised to `14.0+` by `PYRXSynapse`'s
  Podspec at `pod install` time)
- **Android** `minSdk 24` (Android 7.0 Nougat and up)
- JDK 17 for the Android Gradle build

iOS and Android only in 0.1.0. Flutter Web and Flutter Desktop are
explicitly **out of scope** for this release — they're handled in a
future phase. A Flutter Web app that wants push can use the
[`@pyrx/synapse-browser`](https://www.npmjs.com/package/@pyrx/synapse-browser)
JS SDK directly via JS interop.

---

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
`pyrx_synapse_android`. Federation wires the right implementation per
platform — you do **not** add the platform packages to your
`pubspec.yaml` manually.

Then complete the per-platform configuration:

- **iOS** — Apple Developer Program account, APNs key, `aps-environment`
  entitlement, optional `UIBackgroundModes: [remote-notification]`.
  See [`docs/INSTALL-IOS.md`](docs/INSTALL-IOS.md).
- **Android** — Firebase project, `google-services.json`,
  `POST_NOTIFICATIONS` permission for Android 13+.
  See [`docs/INSTALL-ANDROID.md`](docs/INSTALL-ANDROID.md).

---

## Quickstart

```dart
import 'package:pyrx_synapse/pyrx_synapse.dart';

Future<void> main() async {
  // 1. Initialize once at app start, before any other call.
  await Synapse.initialize(const PyrxConfig(
    workspaceId: '<your-workspace-id>',
    apiKey: 'psk_test_<your-key>',
    environment: PyrxEnvironment.sandbox,
  ));

  // 2. Subscribe to the merged Stream<PyrxEvent>. Subscribe EARLY —
  //    the native SDKs replay-buffer the most recent 4 events so a
  //    Dart listener that attaches a few hundred milliseconds after
  //    cold-start still catches a cold-start push tap.
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
        debugPrint(
          'identity ${before?.externalId ?? "(none)"} → '
          '${after.externalId ?? "(anon)"}',
        );
    }
  });

  // 3. Bind a user identity (anonymous → known merge happens server-side).
  await Synapse.identify('user_123', traits: {'plan': 'pro'});

  // 4. Send a tracking event.
  await Synapse.track('order_placed', properties: {'order_id': 'A-42'});

  // 5. Ask the OS for push permission. After this resolves to `granted`,
  //    the SDK registers the device with the backend and is ready to
  //    receive pushes.
  final status = await Synapse.requestPushPermission();
  debugPrint('push permission: $status');
}
```

That's it. Once `requestPushPermission()` returns `granted`, pushes
sent from the PYRX dashboard land on the device. The merged event
stream surfaces every delivery, tap, and identity transition so you
can drive UI updates without polling.

---

## Reading the merged event stream

```dart
// Filter to a single event type — the idiomatic Dart way:
final pushClickStream = Synapse.events
    .where((e) => e is PushClicked)
    .cast<PushClicked>();

pushClickStream.listen((evt) {
  final link = evt.event.deepLink;
  if (link != null) {
    GoRouter.of(context).push(link);
  }
});

// Or consume the whole stream in a StreamBuilder:
StreamBuilder<PyrxEvent>(
  stream: Synapse.events,
  builder: (context, snapshot) {
    final event = snapshot.data;
    return Text('Last event: ${event?.runtimeType ?? "(none)"}');
  },
);
```

See [`docs/STREAMS.md`](docs/STREAMS.md) for the full set of patterns
(BLoC, Riverpod, single-broadcast-via-ChangeNotifier, dispose
discipline), and [`docs/EVENTS.md`](docs/EVENTS.md) for every event
type's payload shape.

---

## API reference

| What | Where |
|---|---|
| Full `Synapse` namespace reference | [`docs/API.md`](docs/API.md) |
| `Stream<PyrxEvent>` consumption patterns | [`docs/STREAMS.md`](docs/STREAMS.md) |
| Per-event payload shapes | [`docs/EVENTS.md`](docs/EVENTS.md) |
| iOS install (Apple Developer, APNs, entitlements) | [`docs/INSTALL-IOS.md`](docs/INSTALL-IOS.md) |
| Android install (Firebase, google-services.json, manifest) | [`docs/INSTALL-ANDROID.md`](docs/INSTALL-ANDROID.md) |
| Migrating from a direct native (Swift/Kotlin) integration | [`docs/MIGRATING-FROM-NATIVE.md`](docs/MIGRATING-FROM-NATIVE.md) |
| Sample app | [`examples/synapse_flutter_demo/`](examples/synapse_flutter_demo/) |

---

## Sample app

A fully-working Flutter app at
[`examples/synapse_flutter_demo/`](examples/synapse_flutter_demo/)
demonstrates every public surface on five separate tabs:

- **Init** — `Synapse.initialize` + `Synapse.debugInfo()` viewer
- **Identity** — `identify` / `alias` / `logout` + live
  `IdentityChanged` panel via a filtered `Synapse.events` subscription
- **Events** — `track` / `screen` + `QueueDrained` counter
- **Push** — `requestPushPermission` + `registerForPushNotifications` +
  filtered subscriptions for `PushReceived` / `PushClicked` /
  `PushReceivedColdStart`
- **Observer** — the full merged `Stream<PyrxEvent>` log with per-type
  counters

Run it:

```bash
cd examples/synapse_flutter_demo

# iOS:
flutter run -d ios

# Android:
flutter run -d android
```

Enter your workspace ID + API key on the Init tab. From the PYRX
dashboard's push composer, send a single push targeting your device —
you'll see the delivery on the Push tab and the merged event on the
Observer tab within ~50ms.

---

## Federated structure

```text
   ┌──────────────────────────┐
   │  pyrx_synapse (umbrella) │  ← apps depend on this
   └────────────┬─────────────┘
                │ depends on
   ┌────────────▼─────────────┐
   │  pyrx_synapse_platform_  │
   │  interface               │
   └────┬───────────────┬─────┘
        │ extended by   │ extended by
   ┌────▼────────┐  ┌───▼──────────┐
   │ pyrx_synapse│  │ pyrx_synapse_│
   │ _ios        │  │ android      │
   └─────────────┘  └──────────────┘
```

Per
[Flutter's federated plugin guidance](https://docs.flutter.dev/packages-and-plugins/developing-packages#federated-plugins),
mirrors `firebase_core` / `firebase_messaging`. Customers add only
`pyrx_synapse` to their `pubspec.yaml`; the other three resolve
transitively.

This shape also future-proofs cross-platform extension — a future
`pyrx_synapse_web` (wrapping `@pyrx/synapse-browser` via JS interop)
can ship without modifying the umbrella or sibling platform packages.

See [Phase 9.3 plan §D3](https://github.com/PYRX-Tech/pyrx-synapse/blob/master/docs/plans/phase-9.3-flutter-sdk-plan-2026-06-27.md#d3)
for the full decision record.

---

## Troubleshooting

### iOS: push permission granted but no token registers

Check that your Bundle ID has APNs configured in Apple Developer
Console and that the `aps-environment` entitlement is set on your
`Runner.entitlements`. The plugin's `register(with:)` calls into
`PYRXSynapse`'s push registrar automatically — if the token never
arrives, the OS isn't issuing it (entitlement issue), not the plugin.

Verify in the Xcode console that
`application:didRegisterForRemoteNotificationsWithDeviceToken:` is
being called. If it isn't, fix the entitlement first.

### iOS: pushes work in TestFlight but not in Xcode dev builds (or vice-versa)

Wrong `aps-environment`. Use `development` for Xcode / EAS dev
builds; use `production` for App Store and TestFlight. The
entitlement value is set in your `Runner.entitlements` file, not in
the SDK — there's no SDK-side toggle for this.

### Android: device registers but no push lands

Verify `google-services.json` is at `android/app/google-services.json`
(not at the project root). Verify the Firebase project ID in that file
matches what the PYRX dashboard shows for your workspace.

On Android 13+, verify the user has granted `POST_NOTIFICATIONS` —
the SDK does NOT auto-request this; your app must call
`Permission.notification.request()` (from `permission_handler` or
similar) before pushes will display.

### `MissingPluginException` at app launch

Run `flutter clean && flutter pub get && cd ios && pod install` (or
the Android equivalent: nothing special, Gradle re-syncs on next
build). If the error persists, the federated resolver may have
cached a stale plugin registry — delete `.dart_tool/` and re-run.

### "Initialize failed: invalid_argument"

The native SDK rejected your `PyrxConfig`. Most common cause: an
empty `workspaceId` or `apiKey`. Less common: re-initializing with a
different config than the first call (the native SDK rejects this —
call `setLogLevel` or `setTrackingEnabled` to mutate state instead of
re-initializing).

### CHANGELOG hasn't bumped but pub.dev shows old docs

Pub.dev's dartdoc generation runs ~5 minutes after publish. Wait and
refresh.

---

## License

MIT — see [LICENSE](./LICENSE).

---

## Contributing

This package is part of the [PYRX](https://pyrx.tech) ecosystem. The
native SDKs live in separate repos:

- [`pyrx-synapse-ios`](https://github.com/PYRX-Tech/pyrx-synapse-ios)
- [`pyrx-synapse-android`](https://github.com/PYRX-Tech/pyrx-synapse-android)

The Phase 9.3 plan that drove this Flutter SDK is in the upstream
[`pyrx.synapse`](https://github.com/PYRX-Tech/pyrx-synapse) monorepo
at
[`docs/plans/phase-9.3-flutter-sdk-plan-2026-06-27.md`](https://github.com/PYRX-Tech/pyrx-synapse/blob/master/docs/plans/phase-9.3-flutter-sdk-plan-2026-06-27.md).
