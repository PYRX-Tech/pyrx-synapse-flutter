# API reference — `Synapse` namespace

Every public method on the `Synapse` static class. Mirrors the 12-method
surface of the native iOS and Android SDKs 1:1 (per the Pigeon
`PyrxSynapseHostApi` contract in
`pyrx_synapse_platform_interface/pigeons/`).

All methods are `static` on the `Synapse` class. The class is not
instantiable — there is exactly one Synapse per app process.

For the merged `Stream<PyrxEvent>` companion (`Synapse.events`), see
[STREAMS.md](./STREAMS.md). For the per-event payload reference, see
[EVENTS.md](./EVENTS.md).

---

## Lifecycle

### `Synapse.initialize(PyrxConfig config) → Future<void>`

Boots the SDK against a Synapse workspace. **MUST** be the first call;
every other method throws (or queues + replays, depending on the
method) if the SDK is uninitialised.

**Idempotent.** A second call with the same `config` is a no-op. A
second call with a differing `config` rejects with a native-side
`invalid_argument` error — to mutate runtime state, use
`setLogLevel` / `setTrackingEnabled` instead.

```dart
await Synapse.initialize(const PyrxConfig(
  workspaceId: '01940a3f-...-...',
  apiKey: 'psk_test_<32 hex>',
  environment: PyrxEnvironment.sandbox,
  baseUrl: null,            // optional — defaults to synapse-events.pyrx.tech
  logLevel: PyrxLogLevel.info, // optional — defaults to info
));
```

| Field | Required | Notes |
|---|---|---|
| `workspaceId` | yes | UUID v4 string. From the PYRX dashboard. |
| `apiKey` | yes | `psk_test_...` (sandbox) or `psk_live_...` (production). |
| `environment` | yes | `production`, `sandbox`, or `staging`. |
| `baseUrl` | no | Override the ingestion base URL. Default: `https://synapse-events.pyrx.tech`. |
| `logLevel` | no | `debug` / `info` / `warning` / `error` / `none`. Default: `info`. |

Throws `ArgumentError` synchronously for empty `workspaceId` /
`apiKey` / `baseUrl`. Async errors from the native side surface as
`PlatformException`.

### `Synapse.setLogLevel(PyrxLogLevel level) → Future<void>`

Mutate the runtime log verbosity after init. Effective immediately.

### `Synapse.debugInfo() → Future<DebugInfo>`

Snapshot of the SDK's internal state. Useful for debug menus and
customer-support bundles.

```dart
final info = await Synapse.debugInfo();
print(info.sdkVersion);
print(info.queueDepth);
print(info.deviceTokenFingerprint);
```

`DebugInfo` fields:

| Field | Type | Meaning |
|---|---|---|
| `sdkVersion` | `String` | The native SDK version that's bridged. |
| `platform` | `String` | `"ios"` or `"android"`. |
| `initialized` | `bool` | True after a successful `initialize`. |
| `workspaceId` | `String?` | Echo of the configured workspace. |
| `environment` | `String?` | Echo of the configured environment. |
| `baseUrl` | `String?` | Resolved base URL (null if SDK default). |
| `logLevel` | `String` | Current verbosity. |
| `anonymousId` | `String?` | SDK-minted anonymous device ID. |
| `externalId` | `String?` | Bound external user ID, if any. |
| `trackingEnabled` | `bool` | Tracking gate state. |
| `queueDepth` | `int` | Number of events waiting to flush. |
| `deviceTokenFingerprint` | `String?` | Truncated APNs/FCM token, or null if not registered. |

---

## Identity

### `Synapse.identify(String externalId, {Map<String, Object?>? traits}) → Future<IdentityResult>`

Bind the current device to an external user identity. The native SDKs
handle the anonymous-to-known merge on the server side — events
captured before this call are reattributed to the merged contact.

```dart
final result = await Synapse.identify(
  'user_42',
  traits: {
    'email': 'jane@example.com',
    'plan': 'pro',
    'signup_at': DateTime.now().toIso8601String(),
  },
);
print(result.contactId); // server-assigned UUID
print(result.path);      // 'new' | 'merge' | 'alias' | 'noop'
```

`traits` is JSON-encoded before crossing the bridge. Values must be
JSON-representable (`String`, `num`, `bool`, `null`, `List`, `Map`).
Non-JSON values (e.g., a `DateTime`) throw `ArgumentError`
synchronously — encode them first.

Throws `ArgumentError` for empty `externalId`.

### `Synapse.alias(String newExternalId) → Future<IdentityResult>`

Rename the active external identity. Common use: the customer changed
their username and you want their event history to carry forward.

Returns the same `IdentityResult` shape as `identify` so callers can
branch on `result.path == 'alias'`.

### `Synapse.logout() → Future<void>`

Drop the current identity and roll a fresh `anonymousId`. The next
`identify` call after a logout creates a new contact (or merges into
an existing one, if the `externalId` is already known on the backend).

---

## Events

### `Synapse.track(String eventName, {Map<String, Object?>? properties}) → Future<void>`

Track a custom event. Returns once the event has been enqueued
locally — **NOT** once it has been delivered to the backend. The
native queue owns delivery + retry + drop semantics; subscribe to
`QueueDrained` on `Synapse.events` to observe successful flushes.

```dart
await Synapse.track('order_placed', properties: {
  'order_id': 'A-42',
  'subtotal': 49.99,
  'currency': 'USD',
});
```

Same `properties` JSON-encoding rules as `identify(traits: ...)`.

Throws `ArgumentError` for empty `eventName`.

### `Synapse.screen(String screenName, {Map<String, Object?>? properties}) → Future<void>`

Track a screen view. Semantically equivalent to `track` but routes
to a screen-specific event type on the backend (the analytics module
treats screens as a first-class entity).

In a real app, wire this into your router's `NavigatorObserver` or
`onGenerateRoute` hook so every screen transition emits one
automatically.

---

## Push

### `Synapse.requestPushPermission({bool alert, bool sound, bool badge}) → Future<PushPermissionStatus>`

Ask the OS for permission to send push notifications. On iOS this
prompts the user; on Android 13+ this prompts via the
`POST_NOTIFICATIONS` runtime permission flow; on Android 12 and below
this returns `granted` immediately (notifications are permitted by
default).

After a `granted` (or `provisional` on iOS) verdict, the SDK
**automatically** triggers registration with APNs / FCM. The resulting
device token registers with `synapse-events.pyrx.tech/v1/devices` via
the native SDK's network layer.

```dart
final status = await Synapse.requestPushPermission(
  alert: true, sound: true, badge: true,
);
switch (status) {
  case PushPermissionStatus.granted:
  case PushPermissionStatus.provisional:
    debugPrint('OK to send push');
  case PushPermissionStatus.denied:
    debugPrint('User declined');
  case PushPermissionStatus.notDetermined:
    debugPrint('Prompt was suppressed by another framework');
}
```

`provisional` is iOS-only — it grants quiet (notification center,
no banner) delivery without prompting. Android always returns
`granted` or `denied`.

### `Synapse.registerForPushNotifications() → Future<void>`

Explicitly trigger an APNs/FCM token registration. On iOS this calls
`UIApplication.shared.registerForRemoteNotifications()`; on Android
this is a no-op (FCM auto-registers via the messaging service in
`synapse-push`).

You usually do NOT need to call this manually —
`requestPushPermission` triggers it automatically after a
`granted`/`provisional` verdict. Call it explicitly only if you've
deferred permission to a later point in the app flow and want to
re-issue registration.

---

## Privacy

### `Synapse.setTrackingEnabled(bool enabled) → Future<void>`

Toggle the SDK's tracking gate. `false` drains the queue and disables
future event capture; identity is preserved. Use this for an
"opt out of analytics" toggle that doesn't sign the user out.

`true` resumes capture.

### `Synapse.deleteUser() → Future<void>`

GDPR delete. Drops local identity, wipes the encrypted credential
store, drains the queue, and asks the backend to forget the contact.
**Irreversible.** Use this when the user requests deletion (Article 17
right to erasure) or when the customer asks you to programmatically
purge a contact (e.g., during account deletion in your own UI).

After this returns, the next call to any other method behaves as a
fresh install — a new `anonymousId` is minted.

---

## Error model

| Source | Surface |
|---|---|
| Synchronous Dart-side validation (empty strings, unencodable JSON) | `ArgumentError` |
| Native-side rejection (invalid config, network, plan limit) | `PlatformException` with a stable `code` field |
| Bridge-level wire drift | `StateError` on the stream (for `Synapse.events`); `PlatformException` for HostApi calls |

Stable `PlatformException.code` values:

| Code | Meaning |
|---|---|
| `not_initialized` | Method called before `initialize` resolved |
| `invalid_argument` | Native side rejected a parameter (e.g., bad `workspaceId`) |
| `network_error` | Backend unreachable / timeout / non-2xx |
| `plan_limit_reached` | Workspace exceeded a plan limit (e.g., monthly events) |
| `permission_denied` | Push permission flow returned `denied` from the OS |
| `unsupported_platform` | Method not available on this platform |

The Dart layer never silently swallows native errors. Wrap calls in
`try / catch (PlatformException e)` to surface them in your UI.
