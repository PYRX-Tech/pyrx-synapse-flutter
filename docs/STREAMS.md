# Consuming `Synapse.events` — the merged event stream

Every observable event the SDK publishes flows through a single
broadcast `Stream<PyrxEvent>` at `Synapse.events`. This document
collects the Dart-idiomatic patterns for consuming it.

For the per-event payload reference, see [EVENTS.md](./EVENTS.md). For
the method API, see [API.md](./API.md).

---

## The 5-event taxonomy

```dart
sealed class PyrxEvent {}

final class PushReceived extends PyrxEvent      { PushReceivedEvent event; }
final class PushClicked extends PyrxEvent       { PushClickedEvent event; }
final class PushReceivedColdStart extends PyrxEvent { PushReceivedEvent event; }
final class QueueDrained extends PyrxEvent      { int count; }
final class IdentityChanged extends PyrxEvent   {
  IdentitySnapshot? before;
  IdentitySnapshot after;
}
```

Sealed + `final class` leaves means Dart 3's exhaustive switch checks
every consumer at compile time. If a future minor adds a 6th variant
(unlikely — see ADR-0005), the compiler flags missing cases on
upgrade.

---

## Subscribe early to catch cold-start events

The native SDKs (PYRXSynapse 0.1.2 / synapse-core 0.1.4) buffer the
most recent 4 events per observer stream. A Dart listener that
attaches a few hundred milliseconds after cold start still receives
buffered events.

**To reliably catch cold-start pushes**, subscribe **before** the user
can navigate away from your splash screen. The right place is:

- In the `initState` of your root widget, OR
- Right after `await Synapse.initialize(...)` resolves in `main()`

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Synapse.initialize(const PyrxConfig(...));

  // Subscribe BEFORE runApp() so cold-start replay is captured.
  Synapse.events.listen(_dispatch);

  runApp(const MyApp());
}
```

---

## Pattern 1 — exhaustive switch (canonical)

```dart
Synapse.events.listen((event) {
  switch (event) {
    case PushReceived(:final event):
      _showInAppToast(event.title, event.body);
    case PushClicked(:final event):
      final link = event.deepLink;
      if (link != null) GoRouter.of(_context).push(link);
    case PushReceivedColdStart(:final event):
      _coldStartLandingRoute(event.pushLogId);
    case QueueDrained(:final count):
      debugPrint('SDK flushed $count events');
    case IdentityChanged(:final before, :final after):
      if (before?.externalId != after.externalId) {
        _userBus.add(UserSwitched(before: before, after: after));
      }
  }
});
```

The compiler enforces exhaustiveness. Adding a `default:` case
suppresses that check — only do that if you genuinely want
forward-compat silent-drop semantics.

---

## Pattern 2 — filter to one event type with `.where().cast<T>()`

For listeners that only care about a single event type, the Dart
idiom is to filter the broadcast stream and re-type with `.cast<T>()`:

```dart
// Cold-start pushes only.
Synapse.events
  .where((e) => e is PushReceivedColdStart)
  .cast<PushReceivedColdStart>()
  .listen((evt) {
    _restoreColdStartRoute(evt.event.pushLogId);
  });

// Identity transitions only.
final identityStream = Synapse.events
  .where((e) => e is IdentityChanged)
  .cast<IdentityChanged>();

identityStream.listen((evt) {
  if (evt.before?.externalId != evt.after.externalId) {
    _refetchUserProfile();
  }
});
```

This pattern keeps each subscription focused on one concern and lets
you reuse the typed sub-stream as a `Stream<T>` in `StreamBuilder` or
in tests.

---

## Pattern 3 — `StreamBuilder` for reactive UI

For widget-tree consumers that re-render on each event:

```dart
StreamBuilder<PyrxEvent>(
  stream: Synapse.events,
  builder: (context, snapshot) {
    if (!snapshot.hasData) return const Text('(waiting for events)');
    final event = snapshot.data!;
    return switch (event) {
      PushReceived(:final event) => Text('Last push: ${event.title}'),
      IdentityChanged(:final after) => Text('Bound as: ${after.externalId}'),
      _ => Text('Other event: ${event.runtimeType}'),
    };
  },
);
```

For a typed sub-stream `StreamBuilder`, pass the filtered stream:

```dart
StreamBuilder<IdentityChanged>(
  stream: Synapse.events
      .where((e) => e is IdentityChanged)
      .cast<IdentityChanged>(),
  builder: (context, snapshot) {
    // ...
  },
);
```

`Synapse.events` is a **broadcast** stream — each `StreamBuilder` adds
its own listener; cancelling that listener when the widget disposes is
StreamBuilder's job, not yours.

---

## Pattern 4 — single subscription + fan-out (recommended for app-wide listeners)

For listeners that must run **at app scope** (e.g., a navigation
router that routes deep links) you want one subscription, not one per
widget. The idiom is a `ChangeNotifier` or `ValueNotifier` that
subscribes once and pushes state outward:

```dart
class PyrxEventBus extends ChangeNotifier {
  PyrxEventBus() {
    _sub = Synapse.events.listen(_onEvent);
  }
  late final StreamSubscription<PyrxEvent> _sub;

  PyrxEvent? _last;
  PyrxEvent? get last => _last;

  void _onEvent(PyrxEvent e) {
    _last = e;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
```

Hold one `PyrxEventBus` at app scope (top-level singleton, `Provider`,
`Riverpod`-managed); have widgets read `bus.last` via
`ListenableBuilder` (or `Consumer` / `ref.watch`). The native event
stream is read once; the UI fan-out is cheap synchronous notification.

This is the pattern the sample app uses for its observer screen —
see `examples/synapse_flutter_demo/lib/src/state/event_log.dart`.

---

## Pattern 5 — BLoC / Riverpod integration

The Flutter SDK does **not** ship BLoC or Riverpod companion packages
in 0.1.0. The merged stream integrates naturally with both:

### BLoC

```dart
class PushBloc extends Bloc<PushEvent, PushState> {
  PushBloc() : super(PushInitial()) {
    on<_NativePushReceived>(_onNativePush);
    on<_NativePushClicked>(_onNativeClick);

    _streamSub = Synapse.events.listen((event) {
      switch (event) {
        case PushReceived(:final event):
          add(_NativePushReceived(event));
        case PushClicked(:final event):
          add(_NativePushClicked(event));
        default:
          break; // ignored
      }
    });
  }

  late final StreamSubscription<PyrxEvent> _streamSub;

  @override
  Future<void> close() async {
    await _streamSub.cancel();
    return super.close();
  }
}
```

### Riverpod

```dart
final pyrxEventStreamProvider = StreamProvider<PyrxEvent>((ref) {
  // Riverpod will auto-dispose this StreamProvider when no widgets
  // are watching; the underlying broadcast stream survives.
  return Synapse.events;
});

final identityStreamProvider = StreamProvider<IdentityChanged>((ref) {
  return Synapse.events
      .where((e) => e is IdentityChanged)
      .cast<IdentityChanged>();
});

class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityStreamProvider);
    return identity.when(
      data: (evt) => Text('Bound: ${evt.after.externalId}'),
      loading: () => const Text('(no identity event yet)'),
      error: (e, _) => Text('Stream error: $e'),
    );
  }
}
```

We may ship optional `pyrx_synapse_bloc` / `pyrx_synapse_riverpod`
companions in a future minor if customers ask. The 0.1.0 surface is
framework-neutral on purpose.

---

## Subscription leaks

Every `Synapse.events.listen(...)` call returns a
`StreamSubscription<PyrxEvent>`. Cancel it on dispose, or the event
handler keeps firing into the void after the widget is gone:

```dart
class _MyWidgetState extends State<MyWidget> {
  StreamSubscription<PyrxEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Synapse.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
```

`StreamBuilder` handles cancellation for you. Manual `listen()` does
not.

In dev mode, leaked subscriptions show up as a stack of `setState
called after dispose` errors when the next event arrives.

---

## Hot reload + multiple subscriptions

The merged stream is **broadcast**, so multiple subscribers each see
every event. Hot reload may double up subscriptions if `initState`
re-runs without `dispose` first — guard against this by storing the
subscription in a field and only re-subscribing if it's null.

In a release build, hot reload doesn't apply and a single
`initState` → `dispose` cycle is guaranteed per widget instance, so
the leak window only exists in development.

---

## Wire-drift error semantics

If the native bridge ever sends an envelope whose discriminator
disagrees with which payload slot is populated, the stream errors
synchronously with `StateError`. Subscribers see the error via the
optional `onError` callback:

```dart
Synapse.events.listen(
  _onEvent,
  onError: (Object err, StackTrace stack) {
    // Should be impossible without a native-SDK bug. Log to your
    // crash reporter so we can investigate.
    FirebaseCrashlytics.instance.recordError(err, stack,
      reason: 'pyrx_synapse wire drift');
  },
);
```

Unknown envelope kinds (i.e., a future native SDK adds a 6th event
type before the Flutter SDK is bumped) are silently dropped — that's
the forward-compat contract. They don't error the stream.
