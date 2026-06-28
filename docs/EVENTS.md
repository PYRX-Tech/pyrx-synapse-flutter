# Event payload reference

Every event published on [`Synapse.events`](./STREAMS.md) — payload
shapes, when each fires, and the invariants you can rely on.

The taxonomy is fixed in [ADR-0005](https://github.com/PYRX-Tech/pyrx-synapse/blob/master/docs/adr/ADR-0005-native-callback-observer-surface.md)
and identical across iOS, Android, React Native, and Flutter SDKs.

---

## `PushReceived`

A push notification was delivered to the foreground (warm-start
delivery).

```dart
final class PushReceived extends PyrxEvent {
  const PushReceived(this.event);
  final PushReceivedEvent event;
}

@immutable
class PushReceivedEvent {
  String title;                           // empty for silent / data-only pushes
  String body;                            // empty for silent / data-only pushes
  String? pushLogId;                      // null for non-Synapse pushes
  Map<String, Object?> data;              // arbitrary APNs/FCM userInfo
  Map<String, PyrxAttributeValue> pyrxAttrs; // Synapse-stamped metadata
  DateTime receivedAt;                    // UTC
}
```

### When it fires

- Push arrives while the app is in the foreground.
- App is in the background AND the push has `content-available: 1`
  (silent push). The push wakes the app for ~30s; if the user does
  not tap, only `PushReceived` fires.

### Does NOT fire when

- App is in the background and the user dismisses the push without
  tapping (the SDK never sees the notification — iOS / Android don't
  notify the app on dismissal).
- App is terminated (cold-start). The first event on app launch is
  `PushReceivedColdStart`, NOT `PushReceived`.

### `data` vs. `pyrxAttrs`

- `data` is the full userInfo / data dict the push was sent with.
  Loosely typed (`Map<String, Object?>`) because the sender controls
  it.
- `pyrxAttrs` is the strongly-typed slot Synapse stamps onto every
  push it sends. Keys include `push_log_id`, `tenant_id`,
  `template_id`, etc. Always present; an empty map (NOT null) for
  pushes that did not carry the `pyrx_attrs` namespace.

See [`docs/STREAMS.md`](./STREAMS.md) for how to read `pyrxAttrs` via
the typed `PyrxAttributeValue` extension accessors.

---

## `PushClicked`

The user tapped a delivered push notification (warm-start tap — the
app was already running, in the foreground or background, when the
tap happened).

```dart
final class PushClicked extends PyrxEvent {
  const PushClicked(this.event);
  final PushClickedEvent event;
}

@immutable
class PushClickedEvent {
  String? pushLogId;
  String? deepLink;                       // sender-attached; null if absent
  String? actionId;                       // for action-button taps; null for body taps
  Map<String, PyrxAttributeValue> pyrxAttrs;
  DateTime clickedAt;                     // UTC
}
```

### When it fires

- App is in the foreground or background AND the user taps the
  notification (or one of its action buttons — `actionId` will be
  non-null).

### Does NOT fire when

- App is terminated (cold-start tap). `PushReceivedColdStart` fires
  instead. **Mutually exclusive with `PushReceivedColdStart` for the
  same tap** — native dedup over a 5-second `push_log_id` window
  guarantees this.

### Routing the deep link

The SDK does NOT auto-navigate. You read `deepLink` and route it via
your router:

```dart
Synapse.events
  .where((e) => e is PushClicked)
  .cast<PushClicked>()
  .listen((evt) {
    final link = evt.event.deepLink;
    if (link != null) {
      GoRouter.of(navigatorKey.currentContext!).push(link);
    }
  });
```

---

## `PushReceivedColdStart`

The OS launched the app FROM a push tap (cold-start tap).

```dart
final class PushReceivedColdStart extends PyrxEvent {
  const PushReceivedColdStart(this.event);
  final PushReceivedEvent event;          // same shape as PushReceived
}
```

### When it fires

- App was terminated (swiped away in app switcher / killed by OS
  memory pressure / cleanly exited).
- User taps a push notification.
- OS launches the app and the SDK initialises.
- The native SDK captures the cold-start payload BEFORE the Dart
  isolate is up; it's then replayed as `PushReceivedColdStart` once a
  Dart subscriber attaches (native replay buffer of 4).

### Does NOT fire when

- The app is already running (foreground or background) — `PushClicked`
  fires instead.

### Why distinguish cold-start from click?

Cold-start routing often needs to wait for navigation to mount.
Treating cold-start as a special case lets your router handle it
differently — e.g., bypass the splash screen, restore deep state, or
defer the route push until after `runApp()` completes.

For the "user-actioned a push" event in general, treat the pair
`PushClicked OR PushReceivedColdStart` as canonical:

```dart
Synapse.events
  .where((e) => e is PushClicked || e is PushReceivedColdStart)
  .listen((evt) {
    final deepLink = switch (evt) {
      PushClicked(:final event) => event.deepLink,
      PushReceivedColdStart(:final event) => event.data['deep_link'] as String?,
      _ => null,
    };
    // route deepLink...
  });
```

---

## `QueueDrained`

The internal event queue successfully flushed `count` events to the
Synapse backend.

```dart
final class QueueDrained extends PyrxEvent {
  const QueueDrained(this.count);
  final int count;                        // always > 0
}
```

### When it fires

- After a successful POST to `/v1/events` that emptied (or partially
  drained) the local queue. The native SDK batches and debounces;
  this typically fires within ~30 seconds of the first queued event.

### Does NOT fire when

- The drain pass was a no-op (zero events in queue).
- The drain failed and the queue is retained for retry. The next
  successful drain pass fires `QueueDrained` for the accumulated
  total.

### Why subscribe

Debug + observability — you can build a "outbox depth" UI affordance
or a Q&A tool that proves the events you called `track()` on are
actually leaving the device. Most production apps don't subscribe.

---

## `IdentityChanged`

The SDK's resolved identity transitioned via `identify`, `alias`, or
`logout`.

```dart
final class IdentityChanged extends PyrxEvent {
  const IdentityChanged({required this.before, required this.after});
  final IdentitySnapshot? before;         // null only on first identify after fresh install
  final IdentitySnapshot after;           // always non-null
}

@immutable
class IdentitySnapshot {
  String? anonymousId;                    // SDK-minted UUID; survives identify/alias
  String? externalId;                     // your user ID; null in anonymous-only sessions
  DateTime snapshotAt;                    // UTC
}
```

### Transition kinds

- **First identify after install** — `before` is `null`,
  `after.externalId` is set.
- **Re-identify with same external ID** — both snapshots equal;
  emitted defensively to confirm the no-op resolved.
- **Login (anonymous → known)** — `before.externalId == null`,
  `after.externalId != null`.
- **Logout (known → anonymous)** — `before.externalId != null`,
  `after.externalId == null`, `after.anonymousId` is a freshly-rolled
  UUID.
- **Switch (known → different known)** — both `externalId`s set and
  unequal. Triggered by `alias()`.

A helper for transition classification:

```dart
enum IdentityTransition { firstIdentify, login, logout, switchUser, noop }

IdentityTransition classify(IdentityChanged evt) {
  final b = evt.before?.externalId;
  final a = evt.after.externalId;
  if (b == null && a == null) return IdentityTransition.noop;
  if (evt.before == null) return IdentityTransition.firstIdentify;
  if (b == null && a != null) return IdentityTransition.login;
  if (b != null && a == null) return IdentityTransition.logout;
  if (b != a) return IdentityTransition.switchUser;
  return IdentityTransition.noop;
}
```

### Use case

Dashboard-style apps that need to refetch user profile data on login
state change use `IdentityChanged` instead of polling
`Synapse.debugInfo().externalId` in a `useEffect`-equivalent:

```dart
Synapse.events
  .where((e) => e is IdentityChanged)
  .cast<IdentityChanged>()
  .listen((evt) {
    final transition = classify(evt);
    switch (transition) {
      case IdentityTransition.login:
      case IdentityTransition.switchUser:
        _refetchUserProfile(evt.after.externalId!);
      case IdentityTransition.logout:
        _clearLocalCaches();
      case _:
        break;
    }
  });
```

---

## What is NOT in the taxonomy (yet)

- **`PushDelivered` (server-confirmed delivery)** — backend-side
  signal, not an SDK event. Surfaced in the dashboard's push-logs
  view, not in the Flutter SDK.
- **`PushDismissed`** — neither iOS nor Android fire a delegate
  callback when the user dismisses a notification without tapping.
  Out of scope.
- **`InAppMessage*`** — IAM is Phase 10 per
  [ADR-0002 D5](https://github.com/PYRX-Tech/pyrx-synapse/blob/master/docs/adr/ADR-0002-billing-and-plan-tiers.md#d5).

The sealed-class taxonomy is intentionally additive — adding a 6th
event variant in a future minor is non-breaking (consumers that didn't
`switch` on it just keep ignoring it; the compiler flags exhaustive
switches that don't handle it so consumers know to update).
