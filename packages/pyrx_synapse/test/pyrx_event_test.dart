// Tests for [PyrxEvent] and [PyrxEvent.fromEnvelope].
//
// What we prove here:
//
//   1. Each of the 5 PyrxEventKind discriminators maps to the
//      correct sealed leaf with a faithful payload conversion.
//   2. A malformed envelope (kind says X but the X slot is null)
//      throws StateError — loud-fail on native-bridge contract
//      violation, NOT a forward-compat ignore.
//   3. The sealed hierarchy supports exhaustive pattern matching at
//      compile time (the test below would fail to compile if a 6th
//      PyrxEvent leaf were added without updating the switch).
//   4. Value equality + hashCode work for every leaf — events can be
//      compared in stream-assertion tests, used as map keys, etc.
//   5. Cold-start payload uses the same PushReceivedEvent shape as
//      warm-start, with the wrapping type as the only discriminator
//      (this is the documented Phase 9.2.1 dedup contract).

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrx_synapse/src/payloads/payloads.dart';
import 'package:pyrx_synapse/src/pyrx_attribute_value.dart';
import 'package:pyrx_synapse/src/pyrx_event.dart';
import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

void main() {
  group('PyrxEvent.fromEnvelope — happy path per discriminator', () {
    test('pushReceived envelope → PushReceived leaf', () {
      final env = PyrxEventEnvelope(
        kind: PyrxEventKind.pushReceived,
        pushReceived: _pushDto(title: 'Hello'),
      );
      final ev = PyrxEvent.fromEnvelope(env);
      expect(ev, isA<PushReceived>());
      expect((ev! as PushReceived).event.title, 'Hello');
    });

    test('pushClicked envelope → PushClicked leaf', () {
      final env = PyrxEventEnvelope(
        kind: PyrxEventKind.pushClicked,
        pushClicked: PushClickedEventDto(
          pushLogId: 'p-1',
          deepLink: 'pyrx://x',
          actionId: null,
          pyrxAttrs: null,
          clickedAt: '2026-06-28T10:00:00.000Z',
        ),
      );
      final ev = PyrxEvent.fromEnvelope(env);
      expect(ev, isA<PushClicked>());
      expect((ev! as PushClicked).event.deepLink, 'pyrx://x');
    });

    test('pushReceivedColdStart envelope → PushReceivedColdStart leaf', () {
      final env = PyrxEventEnvelope(
        kind: PyrxEventKind.pushReceivedColdStart,
        pushReceivedColdStart: _pushDto(title: 'Cold launch'),
      );
      final ev = PyrxEvent.fromEnvelope(env);
      expect(ev, isA<PushReceivedColdStart>());
      expect((ev! as PushReceivedColdStart).event.title, 'Cold launch');
    });

    test('queueDrained envelope → QueueDrained leaf with count', () {
      final env = PyrxEventEnvelope(
        kind: PyrxEventKind.queueDrained,
        queueDrained: QueueDrainedEventDto(count: 7),
      );
      final ev = PyrxEvent.fromEnvelope(env);
      expect(ev, isA<QueueDrained>());
      expect((ev! as QueueDrained).count, 7);
    });

    test('identityChanged envelope → IdentityChanged leaf (login shape)', () {
      final env = PyrxEventEnvelope(
        kind: PyrxEventKind.identityChanged,
        identityChanged: IdentityChangedEventDto(
          before: IdentitySnapshotDto(
            anonymousId: 'anon-1',
            externalId: null,
            snapshotAt: '2026-06-28T10:00:00.000Z',
          ),
          after: IdentitySnapshotDto(
            anonymousId: 'anon-1',
            externalId: 'user-42',
            snapshotAt: '2026-06-28T10:00:05.000Z',
          ),
        ),
      );
      final ev = PyrxEvent.fromEnvelope(env);
      expect(ev, isA<IdentityChanged>());
      final changed = ev! as IdentityChanged;
      expect(changed.before?.externalId, isNull);
      expect(changed.after.externalId, 'user-42');
    });

    test(
      'identityChanged with null before (first identify after fresh install)',
      () {
        final env = PyrxEventEnvelope(
          kind: PyrxEventKind.identityChanged,
          identityChanged: IdentityChangedEventDto(
            after: IdentitySnapshotDto(
              anonymousId: 'anon-1',
              externalId: 'user-42',
              snapshotAt: '2026-06-28T10:00:00.000Z',
            ),
          ),
        );
        final ev = PyrxEvent.fromEnvelope(env);
        expect(ev, isA<IdentityChanged>());
        expect((ev! as IdentityChanged).before, isNull);
      },
    );
  });

  group('PyrxEvent.fromEnvelope — wire-contract violations', () {
    test('kind=pushReceived but pushReceived slot null → StateError', () {
      final env = PyrxEventEnvelope(kind: PyrxEventKind.pushReceived);
      expect(
        () => PyrxEvent.fromEnvelope(env),
        throwsA(isA<StateError>()),
      );
    });

    test('kind=pushClicked but pushClicked slot null → StateError', () {
      final env = PyrxEventEnvelope(kind: PyrxEventKind.pushClicked);
      expect(
        () => PyrxEvent.fromEnvelope(env),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'kind=pushReceivedColdStart but pushReceivedColdStart slot null → '
      'StateError',
      () {
        final env =
            PyrxEventEnvelope(kind: PyrxEventKind.pushReceivedColdStart);
        expect(
          () => PyrxEvent.fromEnvelope(env),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('kind=queueDrained but queueDrained slot null → StateError', () {
      final env = PyrxEventEnvelope(kind: PyrxEventKind.queueDrained);
      expect(
        () => PyrxEvent.fromEnvelope(env),
        throwsA(isA<StateError>()),
      );
    });

    test('kind=identityChanged but identityChanged slot null → StateError', () {
      final env = PyrxEventEnvelope(kind: PyrxEventKind.identityChanged);
      expect(
        () => PyrxEvent.fromEnvelope(env),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('PyrxEvent — sealed hierarchy + exhaustive switch', () {
    test('every variant is reachable in a switch expression', () {
      // This switch is what we want consumers to write. If a 6th
      // sealed leaf were added without updating this function, Dart's
      // exhaustiveness analysis would flag a compile error and this
      // test file would fail to build.
      final samples = <PyrxEvent>[
        PushReceived(_pushPayload()),
        PushClicked(_clickPayload()),
        PushReceivedColdStart(_pushPayload()),
        const QueueDrained(3),
        IdentityChanged(before: null, after: _idSnapshot()),
      ];
      final tags = samples.map(_tagOf).toList();
      expect(tags, ['received', 'clicked', 'cold', 'drained', 'identity']);
    });
  });

  group('PyrxEvent — value equality', () {
    test('PushReceived equals when payload equals', () {
      expect(PushReceived(_pushPayload()), PushReceived(_pushPayload()));
      expect(
        PushReceived(_pushPayload()).hashCode,
        PushReceived(_pushPayload()).hashCode,
      );
    });

    test('PushClicked equals when payload equals', () {
      expect(PushClicked(_clickPayload()), PushClicked(_clickPayload()));
    });

    test('PushReceivedColdStart equals when payload equals', () {
      expect(
        PushReceivedColdStart(_pushPayload()),
        PushReceivedColdStart(_pushPayload()),
      );
    });

    test('QueueDrained equals when count equals', () {
      expect(const QueueDrained(5), const QueueDrained(5));
      expect(const QueueDrained(5), isNot(const QueueDrained(6)));
    });

    test('IdentityChanged equals when before + after equal', () {
      expect(
        IdentityChanged(before: null, after: _idSnapshot()),
        IdentityChanged(before: null, after: _idSnapshot()),
      );
      expect(
        IdentityChanged(before: _idSnapshot(), after: _idSnapshot()),
        IdentityChanged(before: _idSnapshot(), after: _idSnapshot()),
      );
    });

    test(
      'PushReceived != PushReceivedColdStart even when payload is identical',
      () {
        // Cold-start dedup contract: the wrapping type IS the
        // discriminator. Two events with byte-identical payloads but
        // different wrapping types are NOT equal.
        final payload = _pushPayload();
        expect(
          PushReceived(payload),
          isNot(equals(PushReceivedColdStart(payload))),
        );
      },
    );

    test('different sealed leaves are never equal', () {
      expect(
        PushClicked(_clickPayload()),
        isNot(equals(const QueueDrained(1))),
      );
    });
  });

  group('PyrxEvent — toString shape', () {
    test('every leaf names itself in toString', () {
      expect(
        PushReceived(_pushPayload()).toString(),
        startsWith('PushReceived('),
      );
      expect(
        PushClicked(_clickPayload()).toString(),
        startsWith('PushClicked('),
      );
      expect(
        PushReceivedColdStart(_pushPayload()).toString(),
        startsWith('PushReceivedColdStart('),
      );
      expect(const QueueDrained(3).toString(), 'QueueDrained(3)');
      expect(
        IdentityChanged(before: null, after: _idSnapshot()).toString(),
        startsWith('IdentityChanged('),
      );
    });
  });
}

// --------------------------------------------------------------------
// Fixtures
// --------------------------------------------------------------------

PushReceivedEventDto _pushDto({String title = 'Hello'}) => PushReceivedEventDto(
      title: title,
      body: 'world',
      pushLogId: 'log-1',
      data: const <String?, Object?>{'k': 'v'},
      pyrxAttrs: const <String?, Object?>{'template_id': 't-1'},
      receivedAt: '2026-06-28T10:00:00.000Z',
    );

PushReceivedEvent _pushPayload() => PushReceivedEvent(
      title: 'Hello',
      body: 'world',
      pushLogId: 'log-1',
      data: const {'k': 'v'},
      pyrxAttrs: const {'template_id': PyrxAttributeStr('t-1')},
      receivedAt: DateTime.utc(2026, 6, 28, 10),
    );

PushClickedEvent _clickPayload() => PushClickedEvent(
      pushLogId: 'p-1',
      deepLink: 'pyrx://x',
      actionId: null,
      pyrxAttrs: const {},
      clickedAt: DateTime.utc(2026, 6, 28, 10),
    );

IdentitySnapshot _idSnapshot() => IdentitySnapshot(
      anonymousId: 'anon',
      externalId: 'user',
      snapshotAt: DateTime.utc(2026, 6, 28, 10),
    );

/// Exhaustiveness-witness. Adding a new PyrxEvent leaf without
/// updating this switch breaks the build — exactly the contract we
/// want. Updated in Phase 10 PR-2b to cover the two in-app variants.
String _tagOf(PyrxEvent ev) => switch (ev) {
      PushReceived() => 'received',
      PushClicked() => 'clicked',
      PushReceivedColdStart() => 'cold',
      QueueDrained() => 'drained',
      IdentityChanged() => 'identity',
      InAppMessageReceived() => 'in_app_received',
      InAppMessageDismissed() => 'in_app_dismissed',
    };
