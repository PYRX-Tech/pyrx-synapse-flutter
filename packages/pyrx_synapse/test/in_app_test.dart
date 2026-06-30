// Tests for the `Synapse.inApp` namespace and the per-token `ShowToken`
// dispatch machinery. Phase 10 PR-2b.
//
// What we prove here:
//
//   1. Each of the 5 imperative methods delegates to the platform with
//      the right arguments and unwraps Pigeon DTOs into typed shapes.
//   2. Input validation throws ArgumentError BEFORE crossing the bridge
//      (no native round-trip on bad input).
//   3. `show(placement, callback)` returns a `ShowToken` whose
//      `placement` matches and which reports `isDisposed=false`
//      initially.
//   4. `ShowToken.dispose()` is idempotent and routes through
//      `inAppUnregisterShow` exactly once.
//   5. When an `InAppMessageReceived` event flows through the merged
//      event stream, every callback registered for that placement
//      receives the typed `InAppMessage`. Other placements are NOT
//      delivered.
//   6. A buggy callback that throws does NOT poison sibling callbacks
//      OR the underlying subscription.
//   7. The registry reference-counts subscriptions — first show
//      attaches to the event source, last dispose detaches.
//   8. `getActive` returns a defensive copy that mirrors the Pigeon
//      list (un-modifiable).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrx_synapse/pyrx_synapse.dart';

void main() {
  late _InAppFakePlatform fake;
  late StreamController<PyrxEvent> eventController;

  setUp(() {
    fake = _InAppFakePlatform();
    PyrxSynapsePlatform.instance = fake;

    // Inject a deterministic event source so `InAppMessageReceived`
    // dispatch is testable without a Pigeon round-trip.
    eventController = StreamController<PyrxEvent>.broadcast();
    Synapse.inApp.debugSetEventsSource(() => eventController.stream);
  });

  tearDown(() async {
    Synapse.inApp.debugReset();
    Synapse.inApp.debugSetEventsSource(null);
    await eventController.close();
    PyrxSynapsePlatform.instance = MethodChannelPyrxSynapse();
  });

  // ------------------------------------------------------------------
  // show / dispose
  // ------------------------------------------------------------------

  group('Synapse.inApp.show', () {
    test('delegates to inAppShow and returns a ShowToken', () async {
      final token = await Synapse.inApp.show('home_banner', (_) {});
      expect(fake.inAppShowCalls, ['home_banner']);
      expect(token.placement, 'home_banner');
      expect(token.isDisposed, isFalse);
    });

    test('rejects empty placement without calling the bridge', () async {
      expect(
        () => Synapse.inApp.show('', (_) {}),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.inAppShowCalls, isEmpty);
    });

    test('multiple shows allocate distinct subscription ids', () async {
      final t1 = await Synapse.inApp.show('a', (_) {});
      final t2 = await Synapse.inApp.show('a', (_) {});
      expect(t1.isDisposed, isFalse);
      expect(t2.isDisposed, isFalse);
      // Token equality is reference-based; the placement matches but
      // the underlying subscription ids differ (the fake monotonically
      // increments).
      expect(fake.inAppShowCalls, ['a', 'a']);
    });

    test('ShowToken.dispose is idempotent', () async {
      final token = await Synapse.inApp.show('p', (_) {});
      await token.dispose();
      await token.dispose();
      expect(token.isDisposed, isTrue);
      expect(fake.inAppUnregisterShowCalls, hasLength(1));
    });
  });

  // ------------------------------------------------------------------
  // dispatch into per-placement callbacks
  // ------------------------------------------------------------------

  group('per-placement dispatch', () {
    test(
      'InAppMessageReceived event routes to every callback for the placement',
      () async {
        final received = <InAppMessage>[];
        final received2 = <InAppMessage>[];
        final t1 = await Synapse.inApp.show('home_banner', received.add);
        final t2 = await Synapse.inApp.show('home_banner', received2.add);

        final msg = _msg(id: 'asg-1', placement: 'home_banner');
        eventController.add(InAppMessageReceived(msg));
        await Future<void>.delayed(Duration.zero);

        expect(received, [msg]);
        expect(received2, [msg]);

        await t1.dispose();
        await t2.dispose();
      },
    );

    test('messages for OTHER placements are NOT dispatched', () async {
      final received = <InAppMessage>[];
      final token =
          await Synapse.inApp.show('home_banner', received.add);

      eventController.add(
        InAppMessageReceived(_msg(id: 'asg-1', placement: 'settings_modal')),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await token.dispose();
    });

    test('dispose removes the callback before the next event', () async {
      final received = <InAppMessage>[];
      final token = await Synapse.inApp.show('p', received.add);
      await token.dispose();

      eventController.add(InAppMessageReceived(_msg(id: 'a', placement: 'p')));
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
    });

    test(
      'a buggy callback does NOT poison sibling callbacks or the subscription',
      () async {
        // The dispatcher routes host-callback exceptions through
        // [FlutterError.reportError], which by default fails the
        // Flutter test runner. Override the sink for this test so we
        // can confirm the dispatcher survives.
        final originalOnError = FlutterError.onError;
        final swallowed = <FlutterErrorDetails>[];
        FlutterError.onError = swallowed.add;
        addTearDown(() => FlutterError.onError = originalOnError);

        final got = <InAppMessage>[];
        final t1 = await Synapse.inApp.show('p', (_) {
          throw StateError('host bug');
        });
        final t2 = await Synapse.inApp.show('p', got.add);

        eventController.add(
          InAppMessageReceived(_msg(id: 'asg-1', placement: 'p')),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          got,
          hasLength(1),
          reason: 'sibling callback must still receive the event',
        );
        expect(
          swallowed,
          hasLength(1),
          reason: 'host-callback failure must be reported via '
              'FlutterError.onError for Sentry/Crashlytics integration',
        );

        // Second event after the failure to prove the subscription
        // survives.
        eventController.add(
          InAppMessageReceived(_msg(id: 'asg-2', placement: 'p')),
        );
        await Future<void>.delayed(Duration.zero);

        expect(got, hasLength(2));

        await t1.dispose();
        await t2.dispose();
      },
    );
  });

  // ------------------------------------------------------------------
  // ref-count
  // ------------------------------------------------------------------

  group('ShowRegistry ref-count', () {
    test(
      'first show attaches to the events source; last dispose detaches',
      () async {
        expect(Synapse.inApp.debugRefCount, 0);

        final t1 = await Synapse.inApp.show('p', (_) {});
        expect(Synapse.inApp.debugRefCount, 1);
        final t2 = await Synapse.inApp.show('p', (_) {});
        expect(Synapse.inApp.debugRefCount, 2);

        await t1.dispose();
        expect(Synapse.inApp.debugRefCount, 1);
        await t2.dispose();
        expect(Synapse.inApp.debugRefCount, 0);
      },
    );
  });

  // ------------------------------------------------------------------
  // getActive
  // ------------------------------------------------------------------

  group('Synapse.inApp.getActive', () {
    test('returns the bridge response wrapped in typed InAppMessages',
        () async {
      fake.inAppGetActiveResult = [
        InAppMessageDto(
          id: 'asg-1',
          messageId: 'msg-1',
          placement: 'home_banner',
          title: 'T',
          body: 'B',
          imageUrl: null,
          ctas: [
            InAppCtaDto(
              id: 'ok',
              label: 'OK',
              actionType: 'dismiss',
              actionPayload: null,
            ),
          ],
          customData: null,
          expiresAt: '2026-12-31T23:59:59.000Z',
          priority: 5,
        ),
      ];
      final got = await Synapse.inApp.getActive();
      expect(fake.inAppGetActiveCalls, [null]);
      expect(got, hasLength(1));
      expect(got.first.title, 'T');
      expect(got.first.ctas.first.actionType, InAppCtaActionType.dismiss);
      expect(got.first.priority, 5);
      expect(got.first.expiresAt?.toUtc().year, 2026);
    });

    test('placement filter is forwarded as-is', () async {
      await Synapse.inApp.getActive('home_banner');
      expect(fake.inAppGetActiveCalls, ['home_banner']);
    });

    test('returned list is unmodifiable', () async {
      fake.inAppGetActiveResult = [];
      final got = await Synapse.inApp.getActive();
      expect(() => got.add(_msg(id: 'x', placement: 'p')), throwsUnsupportedError);
    });
  });

  // ------------------------------------------------------------------
  // dismiss / markInteracted / refresh
  // ------------------------------------------------------------------

  group('Synapse.inApp.dismiss', () {
    test('forwards messageId + reason', () async {
      await Synapse.inApp.dismiss('msg-1', reason: 'cta_dismissed');
      expect(fake.inAppDismissCalls, hasLength(1));
      expect(fake.inAppDismissCalls.single.key, 'msg-1');
      expect(fake.inAppDismissCalls.single.value, 'cta_dismissed');
    });

    test('reason defaults to null', () async {
      await Synapse.inApp.dismiss('msg-1');
      expect(fake.inAppDismissCalls.single.value, isNull);
    });

    test('rejects empty messageId', () async {
      expect(
        () => Synapse.inApp.dismiss(''),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.inAppDismissCalls, isEmpty);
    });
  });

  group('Synapse.inApp.markInteracted', () {
    test('forwards messageId + ctaId', () async {
      await Synapse.inApp.markInteracted('msg-1', 'cta-1');
      expect(fake.inAppMarkInteractedCalls, hasLength(1));
      expect(fake.inAppMarkInteractedCalls.single.key, 'msg-1');
      expect(fake.inAppMarkInteractedCalls.single.value, 'cta-1');
    });

    test('rejects empty ctaId', () async {
      expect(
        () => Synapse.inApp.markInteracted('msg-1', ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.inAppMarkInteractedCalls, isEmpty);
    });

    test('rejects empty messageId', () async {
      expect(
        () => Synapse.inApp.markInteracted('', 'cta-1'),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.inAppMarkInteractedCalls, isEmpty);
    });
  });

  group('Synapse.inApp.refresh', () {
    test('delegates with no args', () async {
      await Synapse.inApp.refresh();
      expect(fake.inAppRefreshCallCount, 1);
    });
  });

  // ------------------------------------------------------------------
  // InAppMessage / InAppCta payload type unit tests
  // ------------------------------------------------------------------

  group('InAppMessage.fromDto', () {
    test('maps every field including parsed expiresAt + typed customData',
        () {
      final dto = InAppMessageDto(
        id: 'asg-1',
        messageId: 'msg-1',
        placement: 'p',
        title: 't',
        body: 'b',
        imageUrl: 'https://example.com/x.png',
        ctas: [
          InAppCtaDto(
            id: 'a',
            label: 'A',
            actionType: 'deep_link',
            actionPayload: 'myapp://x',
          ),
        ],
        customData: const <String?, Object?>{
          'cohort': 'A',
          'score': 7,
        },
        expiresAt: '2026-12-31T23:59:59.000Z',
        priority: 2,
      );
      final msg = InAppMessage.fromDto(dto);
      expect(msg.id, 'asg-1');
      expect(msg.imageUrl, 'https://example.com/x.png');
      expect(msg.priority, 2);
      expect(msg.expiresAt?.isUtc, isTrue);
      expect(msg.ctas.single.actionType, InAppCtaActionType.deepLink);
      expect(msg.ctas.single.actionPayload, 'myapp://x');
      expect(msg.customData['cohort'], const PyrxAttributeStr('A'));
      expect(msg.customData['score'], const PyrxAttributeInt64(7));
    });

    test('null expiresAt + null customData survive', () {
      final dto = InAppMessageDto(
        id: 'asg-1',
        messageId: 'msg-1',
        placement: 'p',
        title: 't',
        body: 'b',
        imageUrl: null,
        ctas: const [],
        customData: null,
        expiresAt: null,
        priority: 0,
      );
      final msg = InAppMessage.fromDto(dto);
      expect(msg.expiresAt, isNull);
      expect(msg.customData, isEmpty);
    });

    test('unknown CTA action type parses to InAppCtaActionType.unknown', () {
      final dto = InAppMessageDto(
        id: 'asg-1',
        messageId: 'msg-1',
        placement: 'p',
        title: 't',
        body: 'b',
        imageUrl: null,
        ctas: [
          InAppCtaDto(
            id: 'a',
            label: 'A',
            actionType: 'mystery_future_type',
            actionPayload: 'opaque',
          ),
        ],
        customData: null,
        expiresAt: null,
        priority: 0,
      );
      final msg = InAppMessage.fromDto(dto);
      expect(msg.ctas.single.actionType, InAppCtaActionType.unknown);
    });

    test('value equality is field-wise', () {
      InAppMessageDto build({String title = 't'}) => InAppMessageDto(
            id: 'a',
            messageId: 'm',
            placement: 'p',
            title: title,
            body: 'b',
            imageUrl: null,
            ctas: const [],
            customData: null,
            expiresAt: null,
            priority: 0,
          );
      expect(
        InAppMessage.fromDto(build()),
        InAppMessage.fromDto(build()),
      );
      expect(
        InAppMessage.fromDto(build(title: 'a')) ==
            InAppMessage.fromDto(build(title: 'b')),
        isFalse,
      );
    });
  });

  group('InAppCtaActionType.fromWire', () {
    test('every documented action type round-trips', () {
      expect(InAppCtaActionType.fromWire('deep_link'),
          InAppCtaActionType.deepLink);
      expect(InAppCtaActionType.fromWire('dismiss'),
          InAppCtaActionType.dismiss);
      expect(InAppCtaActionType.fromWire('webview'),
          InAppCtaActionType.webview);
      expect(InAppCtaActionType.fromWire('callback'),
          InAppCtaActionType.callback);
    });

    test('unknown values parse to unknown (forward-compat)', () {
      expect(InAppCtaActionType.fromWire('future'),
          InAppCtaActionType.unknown);
      expect(InAppCtaActionType.fromWire(''),
          InAppCtaActionType.unknown);
    });
  });

  // ------------------------------------------------------------------
  // 2 new PyrxEvent variants — value equality + toString
  // ------------------------------------------------------------------

  group('InAppMessageReceived / InAppMessageDismissed sealed leaves', () {
    test('InAppMessageReceived equality is by message', () {
      final msg = _msg(id: 'a', placement: 'p');
      expect(
        InAppMessageReceived(msg),
        InAppMessageReceived(msg),
      );
      expect(
        InAppMessageReceived(msg) ==
            InAppMessageReceived(_msg(id: 'b', placement: 'p')),
        isFalse,
      );
    });

    test('InAppMessageDismissed equality covers messageId + reason', () {
      expect(
        const InAppMessageDismissed(messageId: 'a', reason: null),
        const InAppMessageDismissed(messageId: 'a', reason: null),
      );
      expect(
        const InAppMessageDismissed(messageId: 'a', reason: 'x') ==
            const InAppMessageDismissed(messageId: 'a', reason: 'y'),
        isFalse,
      );
    });

    test('toString includes payload for debugging', () {
      final msg = _msg(id: 'a', placement: 'p');
      expect(InAppMessageReceived(msg).toString(),
          contains('InAppMessageReceived'));
      expect(
        const InAppMessageDismissed(messageId: 'm', reason: 'r').toString(),
        contains('messageId: m'),
      );
    });
  });
}

// --------------------------------------------------------------------
// Test fixtures
// --------------------------------------------------------------------

InAppMessage _msg({required String id, required String placement}) {
  return InAppMessage(
    id: id,
    messageId: 'm-$id',
    placement: placement,
    title: 'Title $id',
    body: 'Body $id',
    imageUrl: null,
    ctas: const [],
    customData: const {},
    expiresAt: null,
    priority: 0,
  );
}

/// Fake platform that records every in-app call and emits per-test
/// fixtures. Methods not used by these tests fall back to the base
/// class's `UnimplementedError` — tests that don't touch them never
/// trip the guard.
class _InAppFakePlatform extends PyrxSynapsePlatform {
  final List<String> inAppShowCalls = [];
  final List<MapEntry<String, int>> inAppUnregisterShowCalls = [];
  final List<String?> inAppGetActiveCalls = [];
  final List<MapEntry<String, String?>> inAppDismissCalls = [];
  final List<MapEntry<String, String>> inAppMarkInteractedCalls = [];
  int inAppRefreshCallCount = 0;

  int _nextSubscriptionId = 0;

  List<InAppMessageDto> inAppGetActiveResult = const [];

  @override
  Future<InAppShowTokenDto> inAppShow(String placement) async {
    inAppShowCalls.add(placement);
    _nextSubscriptionId++;
    return InAppShowTokenDto(
      placement: placement,
      subscriptionId: _nextSubscriptionId,
    );
  }

  @override
  Future<void> inAppUnregisterShow(
    String placement,
    int subscriptionId,
  ) async {
    inAppUnregisterShowCalls.add(MapEntry(placement, subscriptionId));
  }

  @override
  Future<List<InAppMessageDto>> inAppGetActive(String? placement) async {
    inAppGetActiveCalls.add(placement);
    return inAppGetActiveResult;
  }

  @override
  Future<void> inAppDismiss(String messageId, String? reason) async {
    inAppDismissCalls.add(MapEntry(messageId, reason));
  }

  @override
  Future<void> inAppMarkInteracted(String messageId, String ctaId) async {
    inAppMarkInteractedCalls.add(MapEntry(messageId, ctaId));
  }

  @override
  Future<void> inAppRefresh() async {
    inAppRefreshCallCount++;
  }
}
