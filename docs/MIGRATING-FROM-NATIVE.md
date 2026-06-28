# Migrating from a direct native (Swift / Kotlin) integration

You currently integrate the PYRX Synapse iOS SDK
([`PYRXSynapse`](https://github.com/PYRX-Tech/pyrx-synapse-ios)) or
Android SDK
([`tech.pyrx.synapse`](https://github.com/PYRX-Tech/pyrx-synapse-android))
directly in a Flutter app via platform channels you wrote yourself.
You want to swap that for the official `pyrx_synapse` Flutter SDK.

The good news: the `pyrx_synapse` Flutter SDK is a thin wrapper around
the same two native SDKs. Method-for-method, the API surface maps
directly. You should be able to delete every line of your custom
bridging code.

This guide is a method-mapping table + a checklist of what to remove.

---

## What `pyrx_synapse` adds vs. doing it yourself

- A typed Dart API that you don't have to write.
- A merged `Stream<PyrxEvent>` that joins iOS's `AsyncStream` and
  Android's `SharedFlow` into one Dart stream.
- Automatic plugin registration (FlutterAppDelegate auto-install on
  iOS, `onAttachedToEngine`-based install on Android).
- Pigeon-codegen'd MethodChannel + EventChannel wiring with type
  safety across all three languages.
- Federated plugin structure so future platform packages
  (`pyrx_synapse_web`, `pyrx_synapse_macos`) can ship without
  customer changes.
- pub.dev-published versioning so you can `flutter pub upgrade`
  instead of bumping Pod / Gradle constraints by hand.

---

## Method-mapping table

| Native iOS (Swift) | Native Android (Kotlin) | Flutter (`Synapse.*`) |
|---|---|---|
| `Pyrx.shared.initialize(config:)` | `Pyrx.initialize(config)` | `Synapse.initialize(PyrxConfig(...))` |
| `Pyrx.shared.identify(externalId:, traits:)` | `Pyrx.identify(externalId, traits)` | `Synapse.identify(externalId, traits: ...)` |
| `Pyrx.shared.alias(_:)` | `Pyrx.alias(newExternalId)` | `Synapse.alias(newExternalId)` |
| `Pyrx.shared.logout()` | `Pyrx.logout()` | `Synapse.logout()` |
| `Pyrx.shared.track(_:properties:)` | `Pyrx.track(eventName, properties)` | `Synapse.track(eventName, properties: ...)` |
| `Pyrx.shared.screen(_:properties:)` | `Pyrx.screen(screenName, properties)` | `Synapse.screen(screenName, properties: ...)` |
| `Pyrx.shared.requestPushPermission(...)` | `Pyrx.requestPushPermission(...)` | `Synapse.requestPushPermission(...)` |
| `UIApplication.shared.registerForRemoteNotifications()` | `Pyrx.registerForPushNotifications()` | `Synapse.registerForPushNotifications()` |
| `Pyrx.shared.setTrackingEnabled(_:)` | `Pyrx.setTrackingEnabled(enabled)` | `Synapse.setTrackingEnabled(enabled)` |
| `Pyrx.shared.deleteUser()` | `Pyrx.deleteUser()` | `Synapse.deleteUser()` |
| `Pyrx.shared.setLogLevel(_:)` | `Pyrx.setLogLevel(level)` | `Synapse.setLogLevel(PyrxLogLevel.X)` |
| `Pyrx.shared.debugInfo()` | `Pyrx.debugInfo()` | `Synapse.debugInfo()` |

### Observer surface

| Native iOS | Native Android | Flutter |
|---|---|---|
| `for await event in Pyrx.shared.events() { ... }` | `Pyrx.events.collect { event -> ... }` | `Synapse.events.listen((event) { ... })` |

The Dart sealed `PyrxEvent` hierarchy mirrors the iOS Swift enum and
Android Kotlin sealed interface exactly:

| Native | Flutter |
|---|---|
| `case .pushReceived(let payload)` | `case PushReceived(:final event)` |
| `case .pushClicked(let payload)` | `case PushClicked(:final event)` |
| `case .pushReceivedColdStart(let payload)` | `case PushReceivedColdStart(:final event)` |
| `case .queueDrained(let count)` | `case QueueDrained(:final count)` |
| `case .identityChanged(let before, let after)` | `case IdentityChanged(:final before, :final after)` |

---

## Migration steps

### 1. Add `pyrx_synapse` to `pubspec.yaml`

```yaml
dependencies:
  pyrx_synapse: ^0.1.0
```

```bash
flutter pub get
```

### 2. Remove your custom MethodChannel / EventChannel code

Delete the Dart file(s) that defined your custom channel constants
and the corresponding Swift / Kotlin handler classes.

You can verify the federated plugin's iOS and Android implementations
are wired by running `flutter build apk --debug` and
`flutter build ios --simulator --debug`. Both should succeed without
your custom bridge files.

### 3. Replace each call site

Search-and-replace your custom channel calls with the corresponding
`Synapse.*` method per the table above.

If you had a custom Dart wrapper class (e.g., `class PyrxBridge`),
delete it. `Synapse.*` IS the public Dart surface.

### 4. Migrate your event subscription

If you were emitting native events via an EventChannel and parsing
JSON Dart-side, delete that code. Subscribe to `Synapse.events`
directly:

```dart
// Before — your custom channel + manual decoding:
final pushReceivedChannel = EventChannel('com.myapp/synapse/push_received');
pushReceivedChannel.receiveBroadcastStream().listen((data) {
  final map = data as Map<String, dynamic>;
  final title = map['title'] as String;
  // ...
});

// After — typed sealed hierarchy:
Synapse.events
  .where((e) => e is PushReceived)
  .cast<PushReceived>()
  .listen((evt) {
    print('title: ${evt.event.title}');
  });
```

### 5. Remove your AppDelegate / MainActivity glue

The Flutter plugin auto-installs both platforms. Delete:

- Any iOS `AppDelegate.swift` parent-class change you made to
  subclass `PYRXSynapseAppDelegate` (the Flutter plugin handles
  registration via the FlutterAppDelegate plugin chain — your
  AppDelegate goes back to `extends FlutterAppDelegate`).
- Any Android `MainActivity.kt` call to `PyrxPush.install(...)` or
  manifest `<service>` declarations for `PyrxMessagingService`.

If your AppDelegate parent class change broke something else in your
app and you'd kept it for that reason — note that 99% of the time the
auto-install just works. If you have a genuine reason to keep the
manual setup, see `INSTALL-IOS.md` "The optional manual-forwarding
fallback" for the override.

### 6. Update the native SDK version pins (if you'd pinned them)

The Flutter plugin pulls in `PYRXSynapse >= 0.1.2` (iOS) and
`tech.pyrx.synapse:synapse-{core,push} >= 0.1.4` (Android)
transitively. If your `Podfile` or `build.gradle` had explicit pins
that overrode these, remove them — let the Flutter plugin's
declarations win. Only override if you have a specific compatibility
reason.

### 7. Re-test

The wire shape is identical; events that were firing before should
still fire. Spot-check:

- Cold-start push tap routes correctly (use `PushReceivedColdStart`)
- Warm-start push tap routes correctly (use `PushClicked`)
- `IdentityChanged` fires after `identify`/`alias`/`logout`
- `QueueDrained` fires within ~30s of a `track` call (with
  `logLevel: PyrxLogLevel.debug` it's chattier)

---

## What you LOSE in this migration

Honestly, not much:

- **Custom argument types.** If your custom bridge let you pass
  Dart-specific types (e.g., `DateTime`) that survived the bridge
  via your own codec, you'll have to encode them yourself (ISO-8601
  strings, epoch millis, etc.) before passing to the typed
  `properties: Map<String, Object?>` parameter. The Pigeon-shaped
  bridge accepts only JSON-representable primitives.

- **Synchronous return.** Every `Synapse.*` method returns a
  `Future`. If your custom bridge had any synchronous-looking
  getters that read cached state, you'll need to await `debugInfo()`
  for the equivalent.

- **Custom event filtering at the native layer.** The Flutter plugin
  forwards every event variant to Dart. If you'd built a custom
  bridge that suppressed certain events native-side for perf, you'll
  need to filter Dart-side via `.where(...)`. The cost is negligible
  (~5 events/sec at peak in our profiling).

---

## What you GAIN

- **Forever-free benefit from native SDK improvements.** When
  `PYRXSynapse 0.1.3` ships with a tuning improvement, your app
  picks it up on the next `flutter pub upgrade` — no Podfile edits.

- **Type safety across three languages.** Pigeon-generated Dart,
  Swift, and Kotlin code enforces the same wire shape. Adding a
  field to a payload propagates everywhere at codegen time, not at
  runtime via a stringly-typed map lookup.

- **Future cross-platform reach.** When `pyrx_synapse_web` ships
  (wrapping `@pyrx/synapse-browser` via JS interop) or a future
  `pyrx_synapse_macos` ships, your existing call sites work on
  those platforms unchanged. Federated structure absorbs the
  difference.

- **Documentation + sample app maintained for you.** API.md,
  STREAMS.md, EVENTS.md, INSTALL-*.md, the
  `examples/synapse_flutter_demo/` Flutter app — all kept in sync
  with the released SDK.
