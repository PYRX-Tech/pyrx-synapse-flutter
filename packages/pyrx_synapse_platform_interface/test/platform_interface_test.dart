// Smoke tests for the PYRX Synapse Flutter platform-interface package.
//
// PR-1 scope: prove the abstract contract, the default MethodChannel
// implementation, and the Pigeon-generated DTO wire types compile,
// resolve, and behave as documented. We do NOT hit any real platform
// channel here — that's reserved for the integration smoke tests in
// pyrx_synapse_ios / pyrx_synapse_android (PR-1) and end-to-end
// validation against the sample app (PR-3).

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';
// The Pigeon-generated HostApi class is intentionally NOT exported from
// the public library (it's an internal seam). Tests reach into the
// generated file by package URL — that's the only "you may peek behind
// the curtain here" pattern we permit.
// ignore: implementation_imports
import 'package:pyrx_synapse_platform_interface/src/generated/pyrx_synapse_messages.g.dart';

void main() {
  group('PyrxSynapsePlatform', () {
    test('default instance is MethodChannelPyrxSynapse', () {
      // No platform package has run registerWith() in this test
      // process, so the default impl must still be sitting at the
      // instance slot.
      expect(PyrxSynapsePlatform.instance, isA<MethodChannelPyrxSynapse>());
    });

    test('rejects subclasses that bypass the platform-interface token', () {
      expect(
        () => PyrxSynapsePlatform.instance = _BadImpl(),
        throwsA(isA<AssertionError>()),
      );
    });

    test('accepts subclasses that go through super()', () {
      final good = _GoodImpl();
      PyrxSynapsePlatform.instance = good;
      expect(PyrxSynapsePlatform.instance, same(good));
      // Reset for sibling tests so the default impl is restored.
      PyrxSynapsePlatform.instance = MethodChannelPyrxSynapse();
    });
  });

  group('PyrxSynapsePlatform default throws UnimplementedError', () {
    // A subclass that doesn't override anything must surface
    // UnimplementedError on every method, so a misimplemented platform
    // package crashes loudly instead of silently no-op'ing.
    final base = _BaseOnlyImpl();

    test('initialize throws UnimplementedError', () {
      expect(
        () => base.initialize(_initArgs()),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('identify throws UnimplementedError', () {
      expect(
        () => base.identify('user-1', null),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('track throws UnimplementedError', () {
      expect(
        () => base.track('event', null),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('requestPushPermission throws UnimplementedError', () {
      expect(
        () => base.requestPushPermission(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('events() throws UnimplementedError', () {
      expect(
        () => base.events(),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });

  group('PyrxInitArgs DTO', () {
    test('round-trips required fields', () {
      final args = _initArgs();
      expect(args.workspaceId, '00000000-0000-0000-0000-000000000000');
      expect(args.apiKey, 'psk_test_abc');
      expect(args.environment, 'sandbox');
      expect(args.baseUrl, isNull);
      expect(args.logLevel, isNull);
    });
  });

  group('PyrxEventEnvelope DTO', () {
    test('PushReceived envelope carries exactly the push-received payload', () {
      final dto = PushReceivedEventDto(
        title: 'New order',
        body: 'Order #42 is ready',
        data: <String?, Object?>{'order_id': '42'},
        receivedAt: '2026-06-27T12:00:00Z',
      );
      final env = PyrxEventEnvelope(
        kind: PyrxEventKind.pushReceived,
        pushReceived: dto,
      );
      expect(env.kind, PyrxEventKind.pushReceived);
      expect(env.pushReceived, same(dto));
      expect(env.pushClicked, isNull);
      expect(env.identityChanged, isNull);
    });

    test('QueueDrained envelope carries the count', () {
      final env = PyrxEventEnvelope(
        kind: PyrxEventKind.queueDrained,
        queueDrained: QueueDrainedEventDto(count: 7),
      );
      expect(env.queueDrained?.count, 7);
    });

    test('IdentityChanged envelope carries before + after snapshots', () {
      final before = IdentitySnapshotDto(
        anonymousId: 'anon-1',
        externalId: null,
        snapshotAt: '2026-06-27T12:00:00Z',
      );
      final after = IdentitySnapshotDto(
        anonymousId: 'anon-1',
        externalId: 'user-42',
        snapshotAt: '2026-06-27T12:00:05Z',
      );
      final env = PyrxEventEnvelope(
        kind: PyrxEventKind.identityChanged,
        identityChanged: IdentityChangedEventDto(
          before: before,
          after: after,
        ),
      );
      expect(env.identityChanged?.before?.externalId, isNull);
      expect(env.identityChanged?.after.externalId, 'user-42');
    });

    test('all seven PyrxEventKind cases exist (taxonomy is closed)', () {
      // Compile-time exhaustiveness — if PYRXSynapse / synapse-core
      // add an eighth case, this test will fail to compile and force
      // a conscious decision about the Dart-side mapping. Phase 10
      // PR-2b extended the taxonomy from 5 to 7 with the two in-app
      // variants.
      const kinds = PyrxEventKind.values;
      expect(kinds, hasLength(7));
      expect(kinds, contains(PyrxEventKind.pushReceived));
      expect(kinds, contains(PyrxEventKind.pushClicked));
      expect(kinds, contains(PyrxEventKind.pushReceivedColdStart));
      expect(kinds, contains(PyrxEventKind.queueDrained));
      expect(kinds, contains(PyrxEventKind.identityChanged));
      expect(kinds, contains(PyrxEventKind.inAppMessageReceived));
      expect(kinds, contains(PyrxEventKind.inAppMessageDismissed));
    });
  });

  group('MethodChannelPyrxSynapse', () {
    test('returns the provided eventsStream from events()', () async {
      final controller = Stream<PyrxEventEnvelope>.fromIterable([
        PyrxEventEnvelope(
          kind: PyrxEventKind.queueDrained,
          queueDrained: QueueDrainedEventDto(count: 1),
        ),
      ]);
      final impl = MethodChannelPyrxSynapse(
        hostApi: _StubHostApi(),
        eventsStream: controller,
      );
      final received = await impl.events().toList();
      expect(received, hasLength(1));
      expect(received.first.kind, PyrxEventKind.queueDrained);
    });
  });
}

PyrxInitArgs _initArgs() => PyrxInitArgs(
      workspaceId: '00000000-0000-0000-0000-000000000000',
      apiKey: 'psk_test_abc',
      environment: 'sandbox',
    );

/// Subclass that bypasses the token verification — must be rejected.
class _BadImpl implements PyrxSynapsePlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Subclass that goes through super() — must be accepted.
class _GoodImpl extends PyrxSynapsePlatform {}

/// Bare subclass with no overrides — every method falls through to the
/// `UnimplementedError` default. Used to prove the contract is honest
/// about "you must override this".
class _BaseOnlyImpl extends PyrxSynapsePlatform {}

/// HostApi stub used by the MethodChannelPyrxSynapse test. PR-1 only
/// needs the events()-stream-injection path; PR-2 will add a richer
/// HostApi mock when the umbrella API exercises every call.
class _StubHostApi implements PyrxSynapseHostApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Stub HostApi reached: ${invocation.memberName}');
}
