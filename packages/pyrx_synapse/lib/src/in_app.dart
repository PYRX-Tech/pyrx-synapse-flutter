// SynapseInApp — the in-app messaging surface accessible via
// `Synapse.inApp.*`. Phase 10 PR-2b.
//
// Five methods + one `ShowToken` handle, cross-SDK symmetric per
// ADR-0009 D5. Mirrors:
//
//   - Browser:  `synapse('inApp.show'|'inApp.getActive'|...)`
//                (packages/sdk/src/in-app.ts)
//   - iOS:      `Synapse.InApp.show / getActive / dismiss / markInteracted /
//                refresh` (PYRXSynapse 0.2.0)
//   - Android:  `Pyrx.inApp.show / getActive / dismiss / markInteracted /
//                refresh` (synapse-{core,inapp} 0.2.0)
//
// Delegation, not re-implementation
// ---------------------------------
// The 10 lifecycle rules from PR #218 (identity gating, immediate poll
// on identify, coalesced concurrent polls, server-authoritative cache,
// dedupe by assignment id, auto-impression after callback returns,
// soft_degraded interval doubling, plan_limit_reached still surfaces,
// no widget code) all live native-side per ADR-0008. Flutter is a
// thin delegation layer — no polling loop, no cache, no backoff in
// Dart.
//
// What this file owns
// -------------------
//
//   1. The `Synapse.inApp` static namespace, mirroring the
//      `Synapse` class shape.
//   2. The `ShowToken` handle returned by `show()`. Wraps the Pigeon
//      `InAppShowTokenDto` and routes `dispose()` to
//      `inAppUnregisterShow` on the platform interface.
//   3. The per-token callback registry that turns the merged
//      `Synapse.events` stream into per-placement render dispatches.
//      One subscription per umbrella-import to the underlying
//      `events()` stream — multiple `show(...)` calls fan out from
//      that single subscription.
//
// Why a callback dispatcher in Dart
// ---------------------------------
// The native side emits an `inAppMessageReceived` envelope on the
// observer stream PER ADR-0009 D6 (cross-SDK symmetric — no separate
// callback channel). The umbrella turns that observer stream into a
// per-token callback contract so consumers can opt into a single
// placement without manually filtering the merged stream. This is
// the same pattern the iOS/Android natives use internally; we recreate
// it on the Dart side because Pigeon does not synthesise opaque
// closure handles across languages.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

import 'payloads/payloads.dart';
import 'pyrx_event.dart';

/// Render callback signature for [SynapseInApp.show].
///
/// The SDK invokes this callback once per fresh message whose
/// `placement` matches the placement registered. Per ADR-0008 D2, the
/// SDK does NOT render — the callback is where the host app draws the
/// UI. Long-running work inside the callback should be deferred via
/// `unawaited(Future(...))` if you need to touch UI on the next frame.
typedef InAppRenderCallback = void Function(InAppMessage message);

/// Opaque handle returned by [SynapseInApp.show]. Calling [dispose]
/// unregisters the callback both on the native side and inside the
/// Dart-side dispatch registry.
///
/// Implements [Finalizable] semantics through the explicit [dispose]
/// — Dart does not have deterministic deinit; consumers MUST call
/// `dispose()` (or use `Synapse.inApp.disposeAll()` on app shutdown)
/// to avoid leaking the callback past the screen's lifecycle.
///
/// Mirrors the iOS `Synapse.ShowToken` class (which `cancel()`s on
/// deinit) and the Android `ShowToken` interface (an `AutoCloseable`).
class ShowToken {
  ShowToken._({
    required InAppShowTokenDto dto,
    required PyrxSynapsePlatform platform,
    required _ShowRegistry registry,
  })  : _dto = dto,
        _platform = platform,
        _registry = registry;

  final InAppShowTokenDto _dto;
  final PyrxSynapsePlatform _platform;
  final _ShowRegistry _registry;
  bool _disposed = false;

  /// The placement key this token is registered for. Surfaced for
  /// debug menus and inspectors — the dispatch path uses
  /// [InAppShowTokenDto.placement] directly.
  String get placement => _dto.placement;

  /// True after [dispose] has been called. Idempotent — subsequent
  /// calls are no-ops.
  bool get isDisposed => _disposed;

  /// Unregister the callback. Idempotent — calling twice is a silent
  /// no-op. Resolves once the native side has acknowledged the
  /// unregistration; the Dart-side registry is cleared synchronously
  /// so subsequent envelopes for this token are immediately filtered.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _registry.unregister(_dto.placement, _dto.subscriptionId);
    await _platform.inAppUnregisterShow(_dto.placement, _dto.subscriptionId);
  }
}

/// Internal callback registry — maps `(placement, subscriptionId)` to
/// the Dart-side render callback. Single shared instance held by the
/// [SynapseInApp] facade; subscribed once to the merged event stream.
class _ShowRegistry {
  _ShowRegistry();

  /// Outer key: placement. Inner key: subscriptionId.
  ///
  /// Lookups in `dispatch()` are by-placement (the cross-SDK contract
  /// says every observer for placement X sees every message for
  /// placement X), so the two-level structure is hot-path friendly.
  final Map<String, Map<int, InAppRenderCallback>> _byPlacement = {};

  /// Reference-counted subscription to the events stream. The first
  /// `register` call attaches; the last `unregister` detaches. Same
  /// shape as the iOS/Android side's "lazy subscribe-on-first /
  /// cancel-on-last" pattern.
  StreamSubscription<PyrxEvent>? _eventsSub;
  int _refCount = 0;

  /// Source factory — defaults to the umbrella's `Synapse.events`
  /// getter (which itself reads from `PyrxSynapsePlatform.instance`).
  /// Tests can override to inject a deterministic source.
  Stream<PyrxEvent> Function()? _eventsSourceOverride;

  /// Test seam — override the events source. Production code never
  /// touches this; the global `Synapse.inApp` instance reads from
  /// the umbrella `Synapse.events` getter by default.
  @visibleForTesting
  void debugSetEventsSource(Stream<PyrxEvent> Function()? source) {
    _eventsSourceOverride = source;
  }

  void register(
    String placement,
    int subscriptionId,
    InAppRenderCallback callback,
    Stream<PyrxEvent> Function() defaultSource,
  ) {
    final inner = _byPlacement.putIfAbsent(placement, () => {});
    inner[subscriptionId] = callback;
    _refCount++;
    if (_eventsSub == null) {
      final source = _eventsSourceOverride ?? defaultSource;
      _eventsSub = source().listen(_dispatch);
    }
  }

  void unregister(String placement, int subscriptionId) {
    final inner = _byPlacement[placement];
    if (inner == null) return;
    if (inner.remove(subscriptionId) == null) {
      // Already gone — keep the ref count balanced.
      return;
    }
    if (inner.isEmpty) {
      _byPlacement.remove(placement);
    }
    _refCount--;
    if (_refCount <= 0) {
      _refCount = 0;
      _eventsSub?.cancel();
      _eventsSub = null;
    }
  }

  /// Drop every registered callback (does NOT call native-side
  /// unregister — used by [SynapseInApp.debugReset] in tests and on
  /// hot-reload to clear the Dart-side state without round-tripping).
  @visibleForTesting
  void debugReset() {
    _byPlacement.clear();
    _refCount = 0;
    _eventsSub?.cancel();
    _eventsSub = null;
  }

  /// Number of registered placements — used by tests to assert
  /// reference-count correctness.
  @visibleForTesting
  int get refCount => _refCount;

  void _dispatch(PyrxEvent event) {
    if (event is! InAppMessageReceived) return;
    final inner = _byPlacement[event.message.placement];
    if (inner == null) return;
    // Snapshot the callbacks before invoking — a callback that
    // disposes its own token mid-iteration would otherwise mutate
    // the map we're walking.
    final snapshot = List<InAppRenderCallback>.of(inner.values);
    for (final cb in snapshot) {
      try {
        cb(event.message);
      } catch (err, st) {
        // Don't let a buggy host callback poison sibling callbacks OR
        // the underlying event subscription. We route the failure to
        // [FlutterError.reportError] so apps that override
        // [FlutterError.onError] (Sentry / Crashlytics integrations,
        // the test zone's error sink) see the failure, but the
        // synchronous dispatch loop keeps walking through sibling
        // callbacks. Without this isolation, a single buggy host
        // callback would tear down the entire observer subscription
        // and ALL other in-app placements would stop receiving.
        FlutterError.reportError(FlutterErrorDetails(
          exception: err,
          stack: st,
          library: 'pyrx_synapse',
          context: ErrorDescription(
            'while dispatching InAppMessageReceived to a host '
            'render callback for placement "${event.message.placement}"',
          ),
        ));
      }
    }
  }
}

/// In-app messaging surface. Reach it via [Synapse.inApp].
///
/// Five methods — `show / getActive / dismiss / markInteracted / refresh`
/// — cross-SDK symmetric per ADR-0009 D5. The SDK delivers
/// [InAppMessage] data to the host app's render callback; the host
/// draws the UI in whatever style fits its design system. The SDK
/// does NOT render. PYRX UI Kit is deferred to Phase 10.x.
///
/// Lifecycle rules (cross-SDK symmetric per PR #218 / ADR-0008) live
/// native-side: identity-gated polling, immediate poll on identify,
/// concurrent poll coalescing, server-authoritative cache eviction,
/// receive-observer dedupe by assignment id, auto-impression after
/// callback returns, `soft_degraded` interval doubling,
/// `plan_limit_reached` still surfaces. Flutter is delegation.
class SynapseInApp {
  /// Internal — instantiated once by the [Synapse] umbrella.
  SynapseInApp();

  /// Override hook for tests. Production code reads
  /// `PyrxSynapsePlatform.instance` directly.
  PyrxSynapsePlatform get _platform => PyrxSynapsePlatform.instance;

  final _ShowRegistry _registry = _ShowRegistry();

  /// Register a render [callback] for [placement].
  ///
  /// The SDK invokes [callback] once per fresh [InAppMessage] whose
  /// `placement` matches [placement]. The callback runs synchronously
  /// when the event is delivered from the native bridge; host apps
  /// that need to touch widgets should marshal onto the next frame
  /// via `WidgetsBinding.instance.addPostFrameCallback`.
  ///
  /// Triggers an immediate poll on the native side if the SDK has
  /// been identified. If the SDK has not yet been identified, the
  /// registration is buffered native-side and a poll will fire as
  /// soon as identity lands (lifecycle rule 2 of PR #218).
  ///
  /// Returns a [ShowToken]. Hold it for the lifetime of the screen
  /// the placement belongs to; call [ShowToken.dispose] when the
  /// screen unmounts to unregister the callback.
  ///
  /// Multiple concurrent registrations for the same [placement] are
  /// supported — every callback receives every fresh message for
  /// that placement.
  ///
  /// [placement] must be non-empty. Throws [ArgumentError] otherwise
  /// without crossing the bridge.
  Future<ShowToken> show(
    String placement,
    InAppRenderCallback callback,
  ) async {
    if (placement.isEmpty) {
      throw ArgumentError.value(
        placement,
        'placement',
        'must be a non-empty string',
      );
    }
    final dto = await _platform.inAppShow(placement);
    _registry.register(placement, dto.subscriptionId, callback, _eventsSource);
    return ShowToken._(
      dto: dto,
      platform: _platform,
      registry: _registry,
    );
  }

  /// Sync-style read of currently-active messages from the in-memory
  /// cache. Does NOT trigger a poll.
  ///
  /// Returns a defensive copy sorted by priority desc, then expiry asc
  /// (mirrors the cross-SDK contract). Filter to a single placement by
  /// passing the key; pass `null` (the default) to return every cached
  /// message.
  Future<List<InAppMessage>> getActive([String? placement]) async {
    final dtos = await _platform.inAppGetActive(placement);
    return List<InAppMessage>.unmodifiable(dtos.map(InAppMessage.fromDto));
  }

  /// Mark a message dismissed.
  ///
  /// Evicts the message from the in-memory cache, fires
  /// [InAppMessageDismissed] on the observer stream, and POSTs
  /// `/v1/in-app/log` with `event="dismissed"`. [reason] is host-side
  /// observer-only — it does NOT cross the wire (PR-1 backend has no
  /// `reason` field).
  ///
  /// Safe to call with an unknown id — the SDK still emits the
  /// observer event (semantics-of-call, not state-of-cache).
  Future<void> dismiss(String messageId, {String? reason}) {
    if (messageId.isEmpty) {
      throw ArgumentError.value(
        messageId,
        'messageId',
        'must be a non-empty string',
      );
    }
    return _platform.inAppDismiss(messageId, reason);
  }

  /// Mark a message interacted (a CTA was tapped).
  ///
  /// POSTs `/v1/in-app/log` with `event="interacted"` and
  /// `cta_id=ctaId`. Does NOT evict from cache — the host decides
  /// whether interaction implies dismissal (a [InAppCtaActionType.dismiss]
  /// CTA would call [dismiss] separately).
  ///
  /// Per ADR-0009 D5 there is NO `inAppMessageInteracted` observer
  /// event — the host already knows when its own CTA was tapped.
  Future<void> markInteracted(String messageId, String ctaId) {
    if (messageId.isEmpty) {
      throw ArgumentError.value(
        messageId,
        'messageId',
        'must be a non-empty string',
      );
    }
    if (ctaId.isEmpty) {
      throw ArgumentError.value(
        ctaId,
        'ctaId',
        'must be a non-empty string',
      );
    }
    return _platform.inAppMarkInteracted(messageId, ctaId);
  }

  /// Explicit poll trigger. Coalesces with any in-flight poll
  /// (lifecycle rule 4). No-op when no placements are registered or
  /// the SDK is not yet identified.
  ///
  /// Use cases: pull-to-refresh on a screen that hosts an in-app
  /// banner, foreground-resume hook in a `WidgetsBindingObserver`.
  /// The background poll timer (60s default, doubled on
  /// `soft_degraded`) covers most cases without needing explicit
  /// refresh.
  Future<void> refresh() => _platform.inAppRefresh();

  /// Test seam — override the events source for the per-token
  /// dispatch registry. Production code never touches this; the
  /// global registry reads from `Synapse.events` by default.
  @visibleForTesting
  void debugSetEventsSource(Stream<PyrxEvent> Function()? source) {
    _registry.debugSetEventsSource(source);
  }

  /// Test seam — drop every registered callback and detach from the
  /// events stream. Does NOT call native-side unregister. Used by
  /// tests and by hot-reload to clear Dart-side state.
  @visibleForTesting
  void debugReset() => _registry.debugReset();

  /// Test seam — current number of registered callbacks. Used by
  /// tests to assert reference-count correctness.
  @visibleForTesting
  int get debugRefCount => _registry.refCount;

  /// Lazy events-source closure passed to the registry. Reads
  /// `Synapse.events` indirectly so the test seam can override it
  /// without monkey-patching the umbrella class. Defined as a method
  /// (not a getter) so the registry can call it on demand.
  Stream<PyrxEvent> _eventsSource() => _Bridge.events();
}

/// Tiny indirection so the registry can pull `Synapse.events` without
/// importing `synapse.dart` (which would create an import cycle —
/// `synapse.dart` imports `in_app.dart` to expose the namespace).
///
/// `Synapse.events` is the public getter; this internal accessor is
/// the same logic in one place so we don't risk drift.
class _Bridge {
  static Stream<PyrxEvent> events() {
    return PyrxSynapsePlatform.instance
        .events()
        .map(PyrxEvent.fromEnvelope)
        .where((event) => event != null)
        .cast<PyrxEvent>();
  }
}
