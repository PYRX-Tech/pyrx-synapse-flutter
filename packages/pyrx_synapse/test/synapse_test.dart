// Tests for the [Synapse] namespace + merged Stream<PyrxEvent>.
//
// What we prove here:
//
//   1. Every imperative method delegates to the correct
//      PyrxSynapsePlatform method with the correctly-shaped args.
//   2. Enum / DTO conversions at the seam are correct (environment +
//      log-level wire values, PushPermissionStatus parsing,
//      IdentityResult / DebugInfo unwrap).
//   3. Input validation throws ArgumentError BEFORE crossing the
//      bridge (no native round-trip on bad input).
//   4. JSON encoding of traits / properties happens at this seam
//      (matches the Pigeon contract that traitsJson is a JSON
//      string, not a typed map).
//   5. The merged Synapse.events stream maps every envelope kind
//      to the typed sealed leaf.
//   6. Synapse.events is broadcast — multiple subscribers each see
//      every event.
//   7. Cancelling all subscribers releases the underlying source
//      subscription (no leak on widget dispose).
//   8. Malformed envelopes surface as stream errors (loud-fail).
//
// Test strategy:
//   - We install a fake PyrxSynapsePlatform via the package-published
//     setter. Every test resets to a fresh fake in `setUp`. Each
//     fake records its calls so we can assert delegation, and emits
//     events on demand via a StreamController so we can drive the
//     events-stream tests deterministically.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrx_synapse/pyrx_synapse.dart';

void main() {
  late _FakePlatform fake;

  setUp(() {
    fake = _FakePlatform();
    PyrxSynapsePlatform.instance = fake;
  });

  tearDown(() {
    // Restore the default platform so cross-file tests don't see our
    // fake leaking through.
    PyrxSynapsePlatform.instance = MethodChannelPyrxSynapse();
  });

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  group('Synapse.initialize', () {
    test('delegates with mapped enum wire values', () async {
      await Synapse.initialize(const PyrxConfig(
        workspaceId: 'ws-1',
        apiKey: 'psk_test_abc',
        environment: PyrxEnvironment.sandbox,
        logLevel: PyrxLogLevel.debug,
      ));
      expect(fake.initializeCalls, hasLength(1));
      final args = fake.initializeCalls.single;
      expect(args.workspaceId, 'ws-1');
      expect(args.apiKey, 'psk_test_abc');
      expect(args.environment, 'sandbox');
      expect(args.logLevel, 'debug');
      expect(args.baseUrl, isNull);
    });

    test('omits optional fields when not supplied', () async {
      await Synapse.initialize(const PyrxConfig(
        workspaceId: 'ws-1',
        apiKey: 'psk_test_abc',
        environment: PyrxEnvironment.production,
      ));
      final args = fake.initializeCalls.single;
      expect(args.environment, 'production');
      expect(args.baseUrl, isNull);
      expect(args.logLevel, isNull);
    });

    test('rejects empty workspaceId without calling the bridge', () async {
      expect(
        () => Synapse.initialize(const PyrxConfig(
          workspaceId: '',
          apiKey: 'psk_test',
          environment: PyrxEnvironment.production,
        )),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.initializeCalls, isEmpty);
    });

    test('rejects empty apiKey without calling the bridge', () async {
      expect(
        () => Synapse.initialize(const PyrxConfig(
          workspaceId: 'ws',
          apiKey: '',
          environment: PyrxEnvironment.production,
        )),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.initializeCalls, isEmpty);
    });

    test('rejects empty baseUrl (when supplied) without calling the bridge',
        () async {
      expect(
        () => Synapse.initialize(const PyrxConfig(
          workspaceId: 'ws',
          apiKey: 'psk',
          environment: PyrxEnvironment.production,
          baseUrl: '',
        )),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.initializeCalls, isEmpty);
    });
  });

  group('Synapse.setLogLevel', () {
    test('forwards wire value for every enum case', () async {
      for (final level in PyrxLogLevel.values) {
        await Synapse.setLogLevel(level);
      }
      expect(
        fake.setLogLevelCalls,
        ['debug', 'info', 'warning', 'error', 'none'],
      );
    });
  });

  group('Synapse.debugInfo', () {
    test('unwraps the Pigeon DTO into a typed DebugInfo', () async {
      fake.debugInfoResult = PyrxDebugInfo(
        sdkVersion: '0.1.0',
        platform: 'ios',
        initialized: true,
        workspaceId: 'ws-1',
        environment: 'sandbox',
        baseUrl: null,
        logLevel: 'info',
        anonymousId: 'anon-1',
        externalId: 'user-42',
        trackingEnabled: true,
        queueDepth: 0,
        deviceTokenFingerprint: 'abcd',
      );
      final info = await Synapse.debugInfo();
      expect(info.sdkVersion, '0.1.0');
      expect(info.platform, 'ios');
      expect(info.initialized, isTrue);
      expect(info.workspaceId, 'ws-1');
      expect(info.environment, 'sandbox');
      expect(info.externalId, 'user-42');
      expect(info.queueDepth, 0);
      expect(info.deviceTokenFingerprint, 'abcd');
    });
  });

  // ------------------------------------------------------------------
  // Identity
  // ------------------------------------------------------------------

  group('Synapse.identify', () {
    test('encodes traits as JSON before crossing the bridge', () async {
      fake.identifyResult = PyrxIdentityResult(
        contactId: 'c-1',
        path: 'new',
        eventsReattributed: 0,
        devicesReattributed: 0,
      );
      final res = await Synapse.identify(
        'user-42',
        traits: const {'plan': 'pro', 'age': 32, 'active': true},
      );
      expect(fake.identifyCalls, hasLength(1));
      final call = fake.identifyCalls.single;
      expect(call.externalId, 'user-42');
      expect(call.traitsJson, isNotNull);
      // Round-trip the JSON to compare structurally (key order is
      // not guaranteed).
      final decoded = jsonDecode(call.traitsJson!) as Map<String, dynamic>;
      expect(decoded, {'plan': 'pro', 'age': 32, 'active': true});

      expect(res.contactId, 'c-1');
      expect(res.path, 'new');
      expect(res.aliasedExternalId, isNull);
    });

    test('null traits sends null traitsJson', () async {
      fake.identifyResult = PyrxIdentityResult(
        contactId: 'c-1',
        path: 'noop',
        eventsReattributed: 0,
        devicesReattributed: 0,
      );
      await Synapse.identify('user-42');
      expect(fake.identifyCalls.single.traitsJson, isNull);
    });

    test('empty externalId throws ArgumentError without calling the bridge',
        () async {
      expect(
        () => Synapse.identify(''),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.identifyCalls, isEmpty);
    });

    test('non-JSON-serialisable trait value throws ArgumentError', () async {
      expect(
        () => Synapse.identify(
          'u',
          traits: {'when': DateTime.now()}, // DateTime is not JSON-encodable
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.identifyCalls, isEmpty);
    });
  });

  group('Synapse.alias', () {
    test('delegates and unwraps the IdentityResult', () async {
      fake.aliasResult = PyrxIdentityResult(
        contactId: 'c-2',
        path: 'alias',
        aliasedExternalId: 'old-user-id',
        eventsReattributed: 7,
        devicesReattributed: 1,
      );
      final res = await Synapse.alias('new-user-id');
      expect(fake.aliasCalls, ['new-user-id']);
      expect(res.path, 'alias');
      expect(res.aliasedExternalId, 'old-user-id');
      expect(res.eventsReattributed, 7);
      expect(res.devicesReattributed, 1);
    });

    test('rejects empty newExternalId', () async {
      expect(
        () => Synapse.alias(''),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.aliasCalls, isEmpty);
    });
  });

  group('Synapse.logout', () {
    test('delegates with no args', () async {
      await Synapse.logout();
      expect(fake.logoutCalled, isTrue);
    });
  });

  // ------------------------------------------------------------------
  // Events (track / screen)
  // ------------------------------------------------------------------

  group('Synapse.track', () {
    test('encodes properties as JSON before crossing the bridge', () async {
      await Synapse.track(
        'order_placed',
        properties: const {'order_id': '42', 'total': 99.99},
      );
      expect(fake.trackCalls, hasLength(1));
      final call = fake.trackCalls.single;
      expect(call.eventName, 'order_placed');
      final decoded = jsonDecode(call.propertiesJson!) as Map<String, dynamic>;
      expect(decoded, {'order_id': '42', 'total': 99.99});
    });

    test('null properties sends null propertiesJson', () async {
      await Synapse.track('app_opened');
      expect(fake.trackCalls.single.propertiesJson, isNull);
    });

    test('rejects empty eventName', () async {
      expect(
        () => Synapse.track(''),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.trackCalls, isEmpty);
    });
  });

  group('Synapse.screen', () {
    test('delegates with JSON-encoded properties', () async {
      await Synapse.screen(
        'Checkout',
        properties: const {'step': 2},
      );
      expect(fake.screenCalls, hasLength(1));
      final call = fake.screenCalls.single;
      expect(call.screenName, 'Checkout');
      expect(
        jsonDecode(call.propertiesJson!) as Map<String, dynamic>,
        {'step': 2},
      );
    });

    test('rejects empty screenName', () async {
      expect(
        () => Synapse.screen(''),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.screenCalls, isEmpty);
    });
  });

  // ------------------------------------------------------------------
  // Push
  // ------------------------------------------------------------------

  group('Synapse.requestPushPermission', () {
    test('parses every PushPermissionStatus wire value', () async {
      final wires = ['granted', 'denied', 'provisional', 'notDetermined'];
      final expected = [
        PushPermissionStatus.granted,
        PushPermissionStatus.denied,
        PushPermissionStatus.provisional,
        PushPermissionStatus.notDetermined,
      ];
      for (var i = 0; i < wires.length; i++) {
        fake.requestPushPermissionResult =
            PyrxPushPermissionResult(status: wires[i]);
        final got = await Synapse.requestPushPermission();
        expect(got, expected[i]);
      }
    });

    test('forwards alert/sound/badge defaults (all true)', () async {
      fake.requestPushPermissionResult =
          PyrxPushPermissionResult(status: 'granted');
      await Synapse.requestPushPermission();
      final call = fake.requestPushPermissionCalls.single;
      expect(call.alert, isTrue);
      expect(call.sound, isTrue);
      expect(call.badge, isTrue);
    });

    test('forwards alert=false override', () async {
      fake.requestPushPermissionResult =
          PyrxPushPermissionResult(status: 'granted');
      await Synapse.requestPushPermission(alert: false);
      expect(fake.requestPushPermissionCalls.single.alert, isFalse);
    });

    test('throws StateError on unknown wire value (loud-fail)', () async {
      fake.requestPushPermissionResult =
          PyrxPushPermissionResult(status: 'mystery');
      expect(
        () => Synapse.requestPushPermission(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Synapse.registerForPushNotifications', () {
    test('delegates with no args', () async {
      await Synapse.registerForPushNotifications();
      expect(fake.registerForPushNotificationsCalled, isTrue);
    });
  });

  // ------------------------------------------------------------------
  // Privacy
  // ------------------------------------------------------------------

  group('Synapse.setTrackingEnabled', () {
    test('forwards boolean polarity', () async {
      await Synapse.setTrackingEnabled(false);
      await Synapse.setTrackingEnabled(true);
      expect(fake.setTrackingEnabledCalls, [false, true]);
    });
  });

  group('Synapse.deleteUser', () {
    test('delegates with no args', () async {
      await Synapse.deleteUser();
      expect(fake.deleteUserCalled, isTrue);
    });
  });

  // ------------------------------------------------------------------
  // Events stream
  // ------------------------------------------------------------------

  group('Synapse.events', () {
    test('maps a pushReceived envelope to PushReceived', () async {
      final completer = Completer<PyrxEvent>();
      final sub = Synapse.events.listen(completer.complete);

      fake.emit(PyrxEventEnvelope(
        kind: PyrxEventKind.pushReceived,
        pushReceived: PushReceivedEventDto(
          title: 'hi',
          body: 'world',
          data: const <String?, Object?>{},
          receivedAt: '2026-06-28T10:00:00.000Z',
        ),
      ));

      final ev = await completer.future;
      expect(ev, isA<PushReceived>());
      expect((ev as PushReceived).event.title, 'hi');
      await sub.cancel();
    });

    test('maps every envelope kind to its sealed leaf', () async {
      final received = <PyrxEvent>[];
      final sub = Synapse.events.listen(received.add);

      fake.emit(PyrxEventEnvelope(
        kind: PyrxEventKind.pushReceived,
        pushReceived: _pushDto(),
      ));
      fake.emit(PyrxEventEnvelope(
        kind: PyrxEventKind.pushClicked,
        pushClicked: PushClickedEventDto(
          clickedAt: '2026-06-28T10:00:00.000Z',
        ),
      ));
      fake.emit(PyrxEventEnvelope(
        kind: PyrxEventKind.pushReceivedColdStart,
        pushReceivedColdStart: _pushDto(),
      ));
      fake.emit(PyrxEventEnvelope(
        kind: PyrxEventKind.queueDrained,
        queueDrained: QueueDrainedEventDto(count: 3),
      ));
      fake.emit(PyrxEventEnvelope(
        kind: PyrxEventKind.identityChanged,
        identityChanged: IdentityChangedEventDto(
          after: IdentitySnapshotDto(
            anonymousId: 'a',
            externalId: 'u',
            snapshotAt: '2026-06-28T10:00:00.000Z',
          ),
        ),
      ));

      // Give the stream a microtask to drain.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(5));
      expect(received[0], isA<PushReceived>());
      expect(received[1], isA<PushClicked>());
      expect(received[2], isA<PushReceivedColdStart>());
      expect(received[3], isA<QueueDrained>());
      expect(received[4], isA<IdentityChanged>());
      expect((received[3] as QueueDrained).count, 3);

      await sub.cancel();
    });

    test('is broadcast — two subscribers each see every event', () async {
      final a = <PyrxEvent>[];
      final b = <PyrxEvent>[];
      final subA = Synapse.events.listen(a.add);
      final subB = Synapse.events.listen(b.add);

      fake.emit(PyrxEventEnvelope(
        kind: PyrxEventKind.queueDrained,
        queueDrained: QueueDrainedEventDto(count: 1),
      ));
      fake.emit(PyrxEventEnvelope(
        kind: PyrxEventKind.queueDrained,
        queueDrained: QueueDrainedEventDto(count: 2),
      ));

      await Future<void>.delayed(Duration.zero);

      expect(a, hasLength(2));
      expect(b, hasLength(2));
      expect(a.whereType<QueueDrained>().map((e) => e.count).toList(), [1, 2]);
      expect(b.whereType<QueueDrained>().map((e) => e.count).toList(), [1, 2]);

      await subA.cancel();
      await subB.cancel();
    });

    test(
      'first listen attaches to the source; last cancel releases it',
      () async {
        // Broadcast StreamController fires onListen once (when the
        // first subscriber attaches) and onCancel once (when the LAST
        // detaches). Intermediate subscribers don't re-fire onListen.
        // This is the correct contract for the broadcast surface we
        // expose — the umbrella `Synapse.events` is just a typed
        // projection of that controller via .map / .where / .cast.
        expect(fake.eventsSourceIsActive, isFalse);

        final subA = Synapse.events.listen((_) {});
        expect(
          fake.eventsSourceIsActive,
          isTrue,
          reason: 'first listen must attach to the source',
        );

        final subB = Synapse.events.listen((_) {});
        // Still active — broadcast multiplexes, no new attachment.
        expect(fake.eventsSourceIsActive, isTrue);

        await subA.cancel();
        // Still active — subB is still listening.
        expect(fake.eventsSourceIsActive, isTrue);

        await subB.cancel();
        expect(
          fake.eventsSourceIsActive,
          isFalse,
          reason: 'cancelling the LAST subscriber must release the source',
        );
      },
    );

    test(
      'malformed envelope (kind/slot mismatch) surfaces as a stream error',
      () async {
        final errors = <Object>[];
        final sub = Synapse.events.listen(
          (_) {},
          onError: errors.add,
        );
        fake.emit(PyrxEventEnvelope(
          kind: PyrxEventKind.pushReceived,
          // pushReceived slot intentionally not provided
        ));
        await Future<void>.delayed(Duration.zero);
        expect(errors, hasLength(1));
        expect(errors.first, isA<StateError>());
        await sub.cancel();
      },
    );
  });
}

// --------------------------------------------------------------------
// Fixtures + fake platform
// --------------------------------------------------------------------

PushReceivedEventDto _pushDto() => PushReceivedEventDto(
      title: 't',
      body: 'b',
      data: const <String?, Object?>{},
      receivedAt: '2026-06-28T10:00:00.000Z',
    );

class _InitCall {
  _InitCall(this.workspaceId, this.apiKey, this.environment, this.baseUrl,
      this.logLevel);
  final String workspaceId;
  final String apiKey;
  final String environment;
  final String? baseUrl;
  final String? logLevel;
}

class _IdentifyCall {
  _IdentifyCall(this.externalId, this.traitsJson);
  final String externalId;
  final String? traitsJson;
}

class _TrackCall {
  _TrackCall(this.eventName, this.propertiesJson);
  final String eventName;
  final String? propertiesJson;
}

class _ScreenCall {
  _ScreenCall(this.screenName, this.propertiesJson);
  final String screenName;
  final String? propertiesJson;
}

class _PushPermCall {
  _PushPermCall(this.alert, this.sound, this.badge);
  final bool alert;
  final bool sound;
  final bool badge;
}

class _FakePlatform extends PyrxSynapsePlatform {
  // Recorded invocations
  final List<_InitCall> initializeCalls = [];
  final List<String> setLogLevelCalls = [];
  final List<_IdentifyCall> identifyCalls = [];
  final List<String> aliasCalls = [];
  bool logoutCalled = false;
  final List<_TrackCall> trackCalls = [];
  final List<_ScreenCall> screenCalls = [];
  final List<_PushPermCall> requestPushPermissionCalls = [];
  bool registerForPushNotificationsCalled = false;
  final List<bool> setTrackingEnabledCalls = [];
  bool deleteUserCalled = false;

  // Results we want returned from async methods
  PyrxIdentityResult identifyResult = PyrxIdentityResult(
    contactId: 'fake',
    path: 'noop',
    eventsReattributed: 0,
    devicesReattributed: 0,
  );
  PyrxIdentityResult aliasResult = PyrxIdentityResult(
    contactId: 'fake',
    path: 'alias',
    eventsReattributed: 0,
    devicesReattributed: 0,
  );
  PyrxPushPermissionResult requestPushPermissionResult =
      PyrxPushPermissionResult(status: 'granted');
  PyrxDebugInfo debugInfoResult = PyrxDebugInfo(
    sdkVersion: '0.1.0',
    platform: 'ios',
    initialized: false,
    logLevel: 'info',
    trackingEnabled: true,
    queueDepth: 0,
  );

  // Event stream plumbing — a broadcast controller so multiple
  // subscribers can attach concurrently. `eventsSourceIsActive` flips
  // true on first attach and false on last detach, matching the
  // broadcast-controller lifecycle the umbrella relies on (so a
  // subscriber-leak in `Synapse.events` would surface as a
  // "still-active after last cancel" assertion failure).
  late final StreamController<PyrxEventEnvelope> _eventsController =
      StreamController<PyrxEventEnvelope>.broadcast(
    onListen: () => eventsSourceIsActive = true,
    onCancel: () => eventsSourceIsActive = false,
  );
  bool eventsSourceIsActive = false;

  /// Test helper — emit an envelope on the events stream.
  void emit(PyrxEventEnvelope envelope) {
    _eventsController.add(envelope);
  }

  // ----- PyrxSynapsePlatform overrides -------------------------------

  @override
  Future<void> initialize(PyrxInitArgs args) async {
    initializeCalls.add(_InitCall(
      args.workspaceId,
      args.apiKey,
      args.environment,
      args.baseUrl,
      args.logLevel,
    ));
  }

  @override
  Future<void> setLogLevel(String level) async {
    setLogLevelCalls.add(level);
  }

  @override
  Future<PyrxDebugInfo> debugInfo() async => debugInfoResult;

  @override
  Future<PyrxIdentityResult> identify(
      String externalId, String? traitsJson) async {
    identifyCalls.add(_IdentifyCall(externalId, traitsJson));
    return identifyResult;
  }

  @override
  Future<PyrxIdentityResult> alias(String newExternalId) async {
    aliasCalls.add(newExternalId);
    return aliasResult;
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }

  @override
  Future<void> track(String eventName, String? propertiesJson) async {
    trackCalls.add(_TrackCall(eventName, propertiesJson));
  }

  @override
  Future<void> screen(String screenName, String? propertiesJson) async {
    screenCalls.add(_ScreenCall(screenName, propertiesJson));
  }

  @override
  Future<PyrxPushPermissionResult> requestPushPermission({
    bool alert = true,
    bool sound = true,
    bool badge = true,
  }) async {
    requestPushPermissionCalls.add(_PushPermCall(alert, sound, badge));
    return requestPushPermissionResult;
  }

  @override
  Future<void> registerForPushNotifications() async {
    registerForPushNotificationsCalled = true;
  }

  @override
  Future<void> setTrackingEnabled(bool enabled) async {
    setTrackingEnabledCalls.add(enabled);
  }

  @override
  Future<void> deleteUser() async {
    deleteUserCalled = true;
  }

  @override
  Stream<PyrxEventEnvelope> events() => _eventsController.stream;
}
