# Synapse Flutter Demo

A complete Flutter app demonstrating every public surface of the
[`pyrx_synapse`](https://pub.dev/packages/pyrx_synapse) SDK. Runs
against your own PYRX workspace.

## What it shows

Five tabs, one SDK slice each:

- **Init** — `Synapse.initialize(PyrxConfig)` + a `Synapse.debugInfo()`
  viewer pinned to the screen
- **Identity** — `identify(externalId, traits: ...)`,
  `alias(newExternalId)`, `logout()` + a live `IdentityChanged` panel
  fed by a `Synapse.events.where((e) => e is IdentityChanged)`
  filtered subscription
- **Events** — `track(name, properties: ...)` and
  `screen(name, properties: ...)` + a `QueueDrained` counter from the
  same filtered-stream pattern + `setTrackingEnabled(true/false)`
  toggles
- **Push** — `requestPushPermission(alert: ..., sound: ..., badge: ...)`
  with toggle switches + `registerForPushNotifications()` + three
  filtered subscriptions for `PushReceived`, `PushReceivedColdStart`,
  `PushClicked` with last-event payload cards
- **Observer** — the full merged `Stream<PyrxEvent>` consumed once at
  app boot via a shared `EventLog` (ChangeNotifier), with per-type
  counters and a 200-entry rolling log

## Prerequisites

- Flutter `>= 3.24.0` (this sample uses `^3.6.0` Dart so it works on
  Flutter 3.27+ for sure)
- A PYRX workspace with at least one API key
  ([dashboard](https://synapse-app.pyrx.tech) → Settings → API Keys)
- For iOS: a Mac with Xcode 15+ and an Apple Developer Program
  account with APNs configured for the demo's Bundle ID (default:
  `tech.pyrx.synapse.synapseFlutterDemo`)
- For Android: a Firebase project with Cloud Messaging enabled and a
  `google-services.json` downloaded

## 1. Bootstrap the workspace

From the repo root (NOT from this sample's directory):

```bash
dart pub global activate melos
melos bootstrap
```

This resolves the sample's path-dep on the sibling `pyrx_synapse`
package and the four federated package siblings.

If you're cribbing this sample for your own app, change the
`pubspec.yaml` line:

```yaml
dependencies:
  pyrx_synapse:
    path: ../../packages/pyrx_synapse   # ← delete this
  pyrx_synapse: ^0.1.0                  # ← use this instead
```

## 2. iOS — Apple Developer setup

Follow [`docs/INSTALL-IOS.md`](../../docs/INSTALL-IOS.md) end-to-end:

- Create an APNs auth key (`.p8`) in Apple Developer Console and
  upload it to the PYRX dashboard
- Add **Push Notifications** capability in Xcode (Runner target →
  Signing & Capabilities) — this writes the `aps-environment`
  entitlement
- (Recommended) Add **Background Modes** → **Remote notifications**
  for silent-push support

The sample app's default Bundle ID is
`tech.pyrx.synapse.synapseFlutterDemo`. If you change it (in Xcode →
General → Identity), update the dashboard's Apple Push Provider
config to match.

## 3. Android — Firebase setup

Follow [`docs/INSTALL-ANDROID.md`](../../docs/INSTALL-ANDROID.md):

- Create a Firebase project at
  [console.firebase.google.com](https://console.firebase.google.com/)
  and add an Android app using `applicationId =
  tech.pyrx.synapse.synapse_flutter_demo` (or your customisation)
- Download `google-services.json` and place it at
  `android/app/google-services.json` (file is gitignored)
- Generate a service-account JSON for the Firebase project and upload
  it to the PYRX dashboard's Android Push Provider config

## 4. Run

```bash
# From inside examples/synapse_flutter_demo/

# iOS simulator (fastest, but no push delivery — Apple's APNs sandbox
# doesn't deliver to simulators on Apple Silicon Macs as of late 2024;
# use a real device):
flutter run -d ios

# iOS device:
flutter run -d <device-id>

# Android emulator:
flutter run -d emulator-5554

# Android device:
flutter run -d <device-id>
```

The app launches into the **Init** tab.

## 5. Exercise the surfaces

### Initialize

1. On the **Init** tab, enter your `workspaceId` (UUID v4) and `apiKey`
   (`psk_test_...` or `psk_live_...`).
2. Pick environment (`sandbox` for test keys, `production` for live).
3. Tap **Initialize**. Within a second you should see the
   **INITIALIZED** pill turn green and the `Synapse.debugInfo()` card
   populate (sdkVersion, anonymousId, queueDepth, etc).

### Identity

1. Switch to the **Identity** tab.
2. Type an external ID (default `user_123`) and email, tap
   **identify()**. The "Last IdentityResult" card populates with
   `path: 'new'` (or `'merge'` if this user already exists in the
   workspace from a prior session).
3. The "Last IdentityChanged event" card also populates immediately —
   you're seeing the `IdentityChanged` event flow through
   `Synapse.events.where((e) => e is IdentityChanged)` into the screen.

4. Tap **alias()** with a new external ID. Notice the transition
   line shows `SWITCH`.
5. Tap **logout()**. The transition shows `LOGOUT` and the
   `after.externalId` is `<null>` (fresh `anonymousId`).

### Events

1. Switch to the **Events** tab.
2. Tap **Synapse.track("demo.button.pressed")** several times. The
   "track() calls" counter increments.
3. Wait ~30 seconds. The "QueueDrained events" counter should tick up
   as the native SDK flushes the batch.
4. Open the PYRX dashboard → Events view. Your `demo.button.pressed`
   events should appear.

### Push

1. Switch to the **Push** tab.
2. Tap **requestPushPermission()**. Grant permission at the OS prompt.
   The status pill turns **GRANTED** (green) or **PROVISIONAL** (teal,
   iOS only).
3. Wait a few seconds. The Init tab's `deviceToken` field should
   populate with a truncated APNs / FCM token. Open the PYRX
   dashboard → Devices view to confirm the device registered.
4. **From the PYRX dashboard's push composer**, send a single push
   targeting your device. Set both a body AND a deep link (e.g.,
   `myapp://orders/42`).

### Push receipt — foreground

5. Keep the app open and tap **Send** in the dashboard composer.
   Within ~1 second, the Push tab's "Last foreground push
   (PushReceived)" card populates.

### Push receipt — warm-start tap

6. Background the app (swipe up from the bottom, but DON'T kill it
   in the app switcher).
7. Send another push from the dashboard. The notification arrives.
8. Tap the notification. The app foregrounds; the Push tab's "Last
   click (PushClicked)" card populates with the `deepLink` value.

### Push receipt — cold-start tap

9. Fully terminate the app (app switcher → swipe up on the app).
10. Send another push.
11. Tap the notification. The OS launches the app from terminated
    state. Wait for the app to render, then go to the Push tab.
12. The "Last cold-start push (PushReceivedColdStart)" card populates
    — AND the "Last click" card does NOT (native-side dedup
    guarantees exactly one of the two fires per real tap).

### Observer

13. Switch to the **Observer** tab.
14. The per-type counters show what you've seen so far:
    `PushReceived: 1`, `PushClicked: 1`, `PushReceivedColdStart: 1`,
    `QueueDrained: N`, `IdentityChanged: N`.
15. The scrollable log shows the last 200 events in reverse-chronological
    order. Tap **Clear** to reset.

## Troubleshooting

See the [main README's troubleshooting section](../../README.md#troubleshooting).
Common issues specific to this sample:

- **`Synapse.initialize` errors with `invalid_argument`** — check
  your `workspaceId` is a UUID v4 and your `apiKey` is non-empty.
  Empty inputs trigger Dart-side `ArgumentError` before the bridge.

- **`flutter run -d ios` succeeds but no push arrives** — Apple's
  APNs sandbox doesn't always deliver to iOS simulators. Use a real
  device for push testing.

- **`google-services.json` not found** — confirm it's at
  `android/app/google-services.json`. The Gradle plugin looks in
  exactly that path.

- **Tests fail with `MissingPluginException`** — the platform channel
  isn't available in test isolates. The sample's `widget_test.dart`
  is shell-only smoke tests on purpose; it does NOT exercise real
  SDK calls.

## What this sample is NOT

- It's not a production-ready UI. Styling is minimal so the SDK call
  sites are obvious. Don't ship buttons-on-cards as your real
  onboarding.
- It's not a comprehensive test suite. For automated tests, see the
  per-package `test/` directories in `packages/*/test/`.
- It does not demonstrate `go_router` deep-link integration, BLoC /
  Riverpod, or multi-screen routing. Those are app-architecture
  decisions orthogonal to the SDK.
