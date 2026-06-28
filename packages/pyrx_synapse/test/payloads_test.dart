// Wrapper / value-class tests for the typed payload data classes.
//
// What we prove here:
//
//   1. Each `fromDto` constructor maps every field correctly from the
//      Pigeon DTO.
//   2. ISO-8601 timestamps parse into UTC `DateTime`s; malformed
//      strings throw `FormatException` (loud-fail on wire drift).
//   3. `pyrxAttrs` is converted to typed `PyrxAttributeValue`s.
//   4. The loosely-typed `data` map preserves nested shapes from
//      Pigeon's wire format.
//   5. Value equality + `hashCode` are correct (matching pairs equal,
//      mismatched pairs unequal).
//   6. `toString` is informative (debug aid).
//
// We do NOT exercise the Pigeon serialise/deserialise codec here —
// that's the platform-interface package's responsibility (and the
// Pigeon codegen runs its own round-trip tests via `melos run
// pigeon-check`).

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrx_synapse/src/payloads/payloads.dart';
import 'package:pyrx_synapse/src/pyrx_attribute_value.dart';
import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

void main() {
  group('IdentitySnapshot.fromDto', () {
    test('maps all fields and parses snapshotAt into UTC DateTime', () {
      final dto = IdentitySnapshotDto(
        anonymousId: 'anon-uuid',
        externalId: 'user-42',
        snapshotAt: '2026-06-28T10:00:00.000Z',
      );
      final snap = IdentitySnapshot.fromDto(dto);
      expect(snap.anonymousId, 'anon-uuid');
      expect(snap.externalId, 'user-42');
      expect(snap.snapshotAt.isUtc, isTrue);
      expect(snap.snapshotAt.toIso8601String(), '2026-06-28T10:00:00.000Z');
    });

    test('handles null anonymousId + externalId', () {
      final dto = IdentitySnapshotDto(
        anonymousId: null,
        externalId: null,
        snapshotAt: '2026-06-28T10:00:00.000Z',
      );
      final snap = IdentitySnapshot.fromDto(dto);
      expect(snap.anonymousId, isNull);
      expect(snap.externalId, isNull);
    });

    test('non-UTC ISO timestamps are normalised to UTC', () {
      final dto = IdentitySnapshotDto(
        anonymousId: 'a',
        externalId: 'x',
        snapshotAt: '2026-06-28T10:00:00.000+07:00',
      );
      final snap = IdentitySnapshot.fromDto(dto);
      expect(snap.snapshotAt.isUtc, isTrue);
      // Equivalent UTC moment is 03:00:00Z
      expect(snap.snapshotAt.hour, 3);
    });

    test('malformed snapshotAt throws FormatException (loud-fail)', () {
      final dto = IdentitySnapshotDto(
        anonymousId: 'a',
        externalId: 'x',
        snapshotAt: 'not-a-date',
      );
      expect(
        () => IdentitySnapshot.fromDto(dto),
        throwsA(isA<FormatException>()),
      );
    });

    test('equality is value-based across all fields', () {
      final a = IdentitySnapshot(
        anonymousId: 'a',
        externalId: 'x',
        snapshotAt: DateTime.utc(2026, 6, 28, 10),
      );
      final b = IdentitySnapshot(
        anonymousId: 'a',
        externalId: 'x',
        snapshotAt: DateTime.utc(2026, 6, 28, 10),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing externalId is unequal', () {
      final a = IdentitySnapshot(
        anonymousId: 'a',
        externalId: 'x',
        snapshotAt: DateTime.utc(2026, 6, 28, 10),
      );
      final b = IdentitySnapshot(
        anonymousId: 'a',
        externalId: 'y',
        snapshotAt: DateTime.utc(2026, 6, 28, 10),
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes every field for debugging', () {
      final s = IdentitySnapshot(
        anonymousId: 'a',
        externalId: 'x',
        snapshotAt: DateTime.utc(2026, 6, 28, 10),
      );
      final str = s.toString();
      expect(str, contains('IdentitySnapshot'));
      expect(str, contains('a'));
      expect(str, contains('x'));
      expect(str, contains('2026'));
    });
  });

  group('PushReceivedEvent.fromDto', () {
    test('maps every required field with both maps populated', () {
      final dto = PushReceivedEventDto(
        title: 'Order ready',
        body: 'Order #42 is ready',
        pushLogId: 'log-123',
        data: const <String?, Object?>{
          'order_id': '42',
          'priority': 1,
        },
        pyrxAttrs: const <String?, Object?>{
          'template_id': 't-1',
          'tenant_id': 'tenant-a',
          'retry_count': 0,
        },
        receivedAt: '2026-06-28T10:00:00.000Z',
      );
      final ev = PushReceivedEvent.fromDto(dto);
      expect(ev.title, 'Order ready');
      expect(ev.body, 'Order #42 is ready');
      expect(ev.pushLogId, 'log-123');
      expect(ev.data, {
        'order_id': '42',
        'priority': 1,
      });
      expect(
        ev.pyrxAttrs['template_id'],
        const PyrxAttributeStr('t-1'),
      );
      expect(
        ev.pyrxAttrs['tenant_id'],
        const PyrxAttributeStr('tenant-a'),
      );
      expect(
        ev.pyrxAttrs['retry_count'],
        const PyrxAttributeInt64(0),
      );
      expect(ev.receivedAt.isUtc, isTrue);
    });

    test('null pyrxAttrs yields empty typed map (not null)', () {
      final dto = PushReceivedEventDto(
        title: '',
        body: '',
        pushLogId: null,
        data: const <String?, Object?>{},
        pyrxAttrs: null,
        receivedAt: '2026-06-28T10:00:00.000Z',
      );
      final ev = PushReceivedEvent.fromDto(dto);
      expect(ev.pyrxAttrs, isEmpty);
      expect(ev.pushLogId, isNull);
    });

    test('pyrxAttrs with nested list/map decode to typed sealed values', () {
      final dto = PushReceivedEventDto(
        title: 'x',
        body: 'y',
        data: const <String?, Object?>{},
        pyrxAttrs: const <String?, Object?>{
          'tags': <Object?>['admin', 'owner'],
          'meta': <String, Object?>{'verified': true},
        },
        receivedAt: '2026-06-28T10:00:00.000Z',
      );
      final ev = PushReceivedEvent.fromDto(dto);
      expect(
        ev.pyrxAttrs['tags'],
        isA<PyrxAttributeArr>(),
      );
      final tags = ev.pyrxAttrs['tags']! as PyrxAttributeArr;
      expect(tags.value, hasLength(2));
      expect(tags.value.first, const PyrxAttributeStr('admin'));

      expect(ev.pyrxAttrs['meta'], isA<PyrxAttributeObj>());
      final meta = ev.pyrxAttrs['meta']! as PyrxAttributeObj;
      expect(meta.value['verified'], const PyrxAttributeBool(true));
    });

    test('data map preserves nested shapes (loose typing)', () {
      final dto = PushReceivedEventDto(
        title: 't',
        body: 'b',
        data: const <String?, Object?>{
          'nested': <String, Object?>{
            'list': <Object?>[1, 2, 3],
          },
        },
        receivedAt: '2026-06-28T10:00:00.000Z',
      );
      final ev = PushReceivedEvent.fromDto(dto);
      final nested = ev.data['nested']! as Map<dynamic, dynamic>;
      expect(nested['list'], [1, 2, 3]);
    });

    test('data map is unmodifiable', () {
      final dto = PushReceivedEventDto(
        title: 't',
        body: 'b',
        data: const <String?, Object?>{'k': 'v'},
        receivedAt: '2026-06-28T10:00:00.000Z',
      );
      final ev = PushReceivedEvent.fromDto(dto);
      expect(() => ev.data['x'] = 'y', throwsUnsupportedError);
    });

    test('null key in data map is coerced to empty string', () {
      final dto = PushReceivedEventDto(
        title: 't',
        body: 'b',
        data: const <String?, Object?>{null: 'zero', 'k': 'v'},
        receivedAt: '2026-06-28T10:00:00.000Z',
      );
      final ev = PushReceivedEvent.fromDto(dto);
      expect(ev.data[''], 'zero');
      expect(ev.data['k'], 'v');
    });

    test('empty title + body (silent / data-only push)', () {
      final dto = PushReceivedEventDto(
        title: '',
        body: '',
        data: const <String?, Object?>{'foo': 'bar'},
        receivedAt: '2026-06-28T10:00:00.000Z',
      );
      final ev = PushReceivedEvent.fromDto(dto);
      expect(ev.title, '');
      expect(ev.body, '');
      expect(ev.data['foo'], 'bar');
    });

    test('equality matches when every field is equal', () {
      PushReceivedEvent build() => PushReceivedEvent(
            title: 't',
            body: 'b',
            pushLogId: 'p-1',
            data: const {'order': 42},
            pyrxAttrs: const {'k': PyrxAttributeStr('v')},
            receivedAt: DateTime.utc(2026, 6, 28, 10),
          );
      expect(build(), equals(build()));
      expect(build().hashCode, equals(build().hashCode));
    });

    test('equality discriminates on every field', () {
      final base = PushReceivedEvent(
        title: 't',
        body: 'b',
        pushLogId: 'p-1',
        data: const {'k': 'v'},
        pyrxAttrs: const {'a': PyrxAttributeStr('x')},
        receivedAt: DateTime.utc(2026, 6, 28, 10),
      );
      expect(
        base,
        isNot(equals(PushReceivedEvent(
          title: 't2',
          body: 'b',
          pushLogId: 'p-1',
          data: const {'k': 'v'},
          pyrxAttrs: const {'a': PyrxAttributeStr('x')},
          receivedAt: DateTime.utc(2026, 6, 28, 10),
        ))),
        reason: 'differing title must not equal',
      );
      expect(
        base,
        isNot(equals(PushReceivedEvent(
          title: 't',
          body: 'b',
          pushLogId: 'p-1',
          data: const {'k': 'v2'},
          pyrxAttrs: const {'a': PyrxAttributeStr('x')},
          receivedAt: DateTime.utc(2026, 6, 28, 10),
        ))),
        reason: 'differing data value must not equal',
      );
      expect(
        base,
        isNot(equals(PushReceivedEvent(
          title: 't',
          body: 'b',
          pushLogId: 'p-1',
          data: const {'k': 'v'},
          pyrxAttrs: const {'a': PyrxAttributeStr('y')},
          receivedAt: DateTime.utc(2026, 6, 28, 10),
        ))),
        reason: 'differing pyrxAttrs value must not equal',
      );
    });

    test('malformed receivedAt throws FormatException', () {
      final dto = PushReceivedEventDto(
        title: 't',
        body: 'b',
        data: const <String?, Object?>{},
        receivedAt: 'nope',
      );
      expect(
        () => PushReceivedEvent.fromDto(dto),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('PushClickedEvent.fromDto', () {
    test('maps every required field with maximal payload', () {
      final dto = PushClickedEventDto(
        pushLogId: 'log-456',
        deepLink: 'pyrx://orders/42',
        actionId: 'OPEN_ORDER',
        pyrxAttrs: const <String?, Object?>{
          'template_id': 't-2',
        },
        clickedAt: '2026-06-28T11:00:00.000Z',
      );
      final ev = PushClickedEvent.fromDto(dto);
      expect(ev.pushLogId, 'log-456');
      expect(ev.deepLink, 'pyrx://orders/42');
      expect(ev.actionId, 'OPEN_ORDER');
      expect(
        ev.pyrxAttrs['template_id'],
        const PyrxAttributeStr('t-2'),
      );
      expect(ev.clickedAt.isUtc, isTrue);
    });

    test('all-null optional fields (plain body tap on a non-Synapse push)', () {
      final dto = PushClickedEventDto(
        pushLogId: null,
        deepLink: null,
        actionId: null,
        pyrxAttrs: null,
        clickedAt: '2026-06-28T11:00:00.000Z',
      );
      final ev = PushClickedEvent.fromDto(dto);
      expect(ev.pushLogId, isNull);
      expect(ev.deepLink, isNull);
      expect(ev.actionId, isNull);
      expect(ev.pyrxAttrs, isEmpty);
    });

    test('equality matches when every field is equal', () {
      PushClickedEvent build() => PushClickedEvent(
            pushLogId: 'p',
            deepLink: 'd',
            actionId: 'a',
            pyrxAttrs: const {'k': PyrxAttributeBool(true)},
            clickedAt: DateTime.utc(2026, 6, 28, 11),
          );
      expect(build(), equals(build()));
      expect(build().hashCode, equals(build().hashCode));
    });

    test('equality discriminates on actionId', () {
      final a = PushClickedEvent(
        pushLogId: 'p',
        deepLink: 'd',
        actionId: 'ACTION_A',
        pyrxAttrs: const {},
        clickedAt: DateTime.utc(2026, 6, 28, 11),
      );
      final b = PushClickedEvent(
        pushLogId: 'p',
        deepLink: 'd',
        actionId: 'ACTION_B',
        pyrxAttrs: const {},
        clickedAt: DateTime.utc(2026, 6, 28, 11),
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes deepLink + actionId for debugging', () {
      final ev = PushClickedEvent(
        pushLogId: 'p',
        deepLink: 'pyrx://x',
        actionId: 'TAP',
        pyrxAttrs: const {},
        clickedAt: DateTime.utc(2026, 6, 28, 11),
      );
      final s = ev.toString();
      expect(s, contains('PushClickedEvent'));
      expect(s, contains('pyrx://x'));
      expect(s, contains('TAP'));
    });

    test('malformed clickedAt throws FormatException', () {
      final dto = PushClickedEventDto(
        clickedAt: 'bad',
      );
      expect(
        () => PushClickedEvent.fromDto(dto),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
