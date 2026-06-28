// Round-trip and equality tests for [PyrxAttributeValue].
//
// What we prove here:
//
//   1. fromJson recognises every JSON-representable leaf type and
//      rejects unsupported runtime types loudly.
//   2. toJson is the inverse of fromJson for every leaf + nested
//      shape (with the documented "all output Map keys are String"
//      exception).
//   3. The sealed-class hierarchy supports exhaustive pattern matching
//      — the test below relies on this at compile time.
//   4. NaN-aware equality on PyrxAttributeDbl works in both
//      directions (NaN == NaN, hash codes match).
//   5. PyrxAttributeNull is a value-equal singleton.
//   6. PyrxAttributeArr / PyrxAttributeObj are deeply equal and
//      preserve unmodifiability.
//   7. PyrxAttributeValue.mapFromJson handles the null / empty / shaped
//      cases the payload data classes will pass through.

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrx_synapse/src/pyrx_attribute_value.dart';

void main() {
  group('PyrxAttributeValue.fromJson — leaf recognition', () {
    test('null → PyrxAttributeNull', () {
      expect(PyrxAttributeValue.fromJson(null), const PyrxAttributeNull());
    });

    test('String → PyrxAttributeStr', () {
      expect(
        PyrxAttributeValue.fromJson('hi'),
        const PyrxAttributeStr('hi'),
      );
    });

    test('empty String → PyrxAttributeStr("")', () {
      expect(
        PyrxAttributeValue.fromJson(''),
        const PyrxAttributeStr(''),
      );
    });

    test('bool → PyrxAttributeBool (both polarities)', () {
      expect(
        PyrxAttributeValue.fromJson(true),
        const PyrxAttributeBool(true),
      );
      expect(
        PyrxAttributeValue.fromJson(false),
        const PyrxAttributeBool(false),
      );
    });

    test('int → PyrxAttributeInt64 (positive / negative / zero / large)', () {
      expect(
        PyrxAttributeValue.fromJson(0),
        const PyrxAttributeInt64(0),
      );
      expect(
        PyrxAttributeValue.fromJson(-42),
        const PyrxAttributeInt64(-42),
      );
      // Below 2^53 for double-safe; above that to prove 64-bit fidelity.
      expect(
        PyrxAttributeValue.fromJson(9007199254740993),
        const PyrxAttributeInt64(9007199254740993),
      );
    });

    test('double → PyrxAttributeDbl (finite / infinity / NaN)', () {
      expect(
        PyrxAttributeValue.fromJson(3.14),
        const PyrxAttributeDbl(3.14),
      );
      expect(
        PyrxAttributeValue.fromJson(double.infinity),
        const PyrxAttributeDbl(double.infinity),
      );
      expect(
        PyrxAttributeValue.fromJson(double.negativeInfinity),
        const PyrxAttributeDbl(double.negativeInfinity),
      );
      // NaN equality is special — see dedicated group below.
      final nan = PyrxAttributeValue.fromJson(double.nan);
      expect(nan, isA<PyrxAttributeDbl>());
      expect((nan as PyrxAttributeDbl).value.isNaN, isTrue);
    });

    test('empty List → PyrxAttributeArr with empty unmodifiable list', () {
      final v = PyrxAttributeValue.fromJson(const <Object?>[]);
      expect(v, isA<PyrxAttributeArr>());
      expect((v as PyrxAttributeArr).value, isEmpty);
      expect(
        () => v.value.add(const PyrxAttributeNull()),
        throwsUnsupportedError,
      );
    });

    test('empty Map → PyrxAttributeObj with empty unmodifiable map', () {
      final v = PyrxAttributeValue.fromJson(const <String, Object?>{});
      expect(v, isA<PyrxAttributeObj>());
      expect((v as PyrxAttributeObj).value, isEmpty);
      expect(
        () => v.value['k'] = const PyrxAttributeNull(),
        throwsUnsupportedError,
      );
    });

    test('unsupported runtime type throws ArgumentError', () {
      expect(
        () => PyrxAttributeValue.fromJson(DateTime.now()),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PyrxAttributeValue.fromJson(const <int>{1, 2, 3}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('PyrxAttributeValue — round-trip identity (fromJson → toJson)', () {
    test('null leaves are stable', () {
      expect(PyrxAttributeValue.fromJson(null).toJson(), isNull);
    });

    test('String / int / bool / double leaves are stable', () {
      for (final raw in <Object?>['x', '', 0, -1, 42, true, false, 1.5]) {
        expect(
          PyrxAttributeValue.fromJson(raw).toJson(),
          equals(raw),
          reason: 'round-trip failed for $raw (${raw.runtimeType})',
        );
      }
    });

    test('large int (above 2^53) round-trips with 64-bit fidelity', () {
      const raw = 9007199254740993;
      expect(PyrxAttributeValue.fromJson(raw).toJson(), equals(raw));
    });

    test('double.infinity / negativeInfinity round-trip', () {
      expect(
        PyrxAttributeValue.fromJson(double.infinity).toJson(),
        equals(double.infinity),
      );
      expect(
        PyrxAttributeValue.fromJson(double.negativeInfinity).toJson(),
        equals(double.negativeInfinity),
      );
    });

    test('NaN round-trips (value still isNaN after toJson)', () {
      final raw = PyrxAttributeValue.fromJson(double.nan).toJson();
      expect(raw, isA<double>());
      expect((raw as double).isNaN, isTrue);
    });

    test('shallow list round-trips element-wise', () {
      final raw = <Object?>['s', 1, true, null, 2.5];
      final out = PyrxAttributeValue.fromJson(raw).toJson();
      expect(out, equals(raw));
    });

    test('shallow map round-trips key-for-key', () {
      final raw = <String, Object?>{
        's': 'hi',
        'i': 7,
        'b': false,
        'n': null,
      };
      final out = PyrxAttributeValue.fromJson(raw).toJson();
      expect(out, equals(raw));
    });

    test('deeply nested mixed list-of-maps-of-lists round-trips', () {
      final raw = <Object?>[
        <String, Object?>{
          'name': 'Trieu',
          'tags': <Object?>['admin', 'owner'],
          'profile': <String, Object?>{
            'age': 32,
            'verified': true,
            'metrics': <Object?>[1, 2, 3, null],
          },
        },
        null,
        42,
      ];
      final out = PyrxAttributeValue.fromJson(raw).toJson();
      expect(out, equals(raw));
    });

    test('Map with non-String keys is coerced to String in toJson output', () {
      // Pigeon's `Map<String?, Object?>` permits null keys; the typed
      // Map output is always String-keyed. This is the documented
      // exception to the round-trip identity rule.
      final raw = <Object?, Object?>{null: 1, 'a': 2};
      final v = PyrxAttributeValue.fromJson(raw);
      final out = v.toJson() as Map<Object?, Object?>;
      expect(out.keys, containsAll(<Object?>['', 'a']));
      expect(out[''], 1);
      expect(out['a'], 2);
    });
  });

  group('PyrxAttributeValue — equality + hashCode', () {
    test('PyrxAttributeStr equality is value-based', () {
      expect(const PyrxAttributeStr('x'), const PyrxAttributeStr('x'));
      expect(
        const PyrxAttributeStr('x').hashCode,
        const PyrxAttributeStr('x').hashCode,
      );
      expect(
        const PyrxAttributeStr('x'),
        isNot(const PyrxAttributeStr('y')),
      );
    });

    test('PyrxAttributeInt64 / PyrxAttributeBool equality is value-based', () {
      expect(const PyrxAttributeInt64(7), const PyrxAttributeInt64(7));
      expect(
        const PyrxAttributeInt64(7),
        isNot(const PyrxAttributeInt64(8)),
      );
      expect(const PyrxAttributeBool(true), const PyrxAttributeBool(true));
      expect(
        const PyrxAttributeBool(true),
        isNot(const PyrxAttributeBool(false)),
      );
    });

    test('PyrxAttributeDbl NaN == NaN (and hash codes match)', () {
      const a = PyrxAttributeDbl(double.nan);
      const b = PyrxAttributeDbl(double.nan);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('PyrxAttributeDbl finite values equal value-wise', () {
      expect(const PyrxAttributeDbl(1.5), const PyrxAttributeDbl(1.5));
      expect(
        const PyrxAttributeDbl(1.5),
        isNot(const PyrxAttributeDbl(1.6)),
      );
    });

    test('PyrxAttributeNull is a value-equal singleton', () {
      expect(const PyrxAttributeNull(), const PyrxAttributeNull());
      expect(
        const PyrxAttributeNull().hashCode,
        const PyrxAttributeNull().hashCode,
      );
      // identical() reflects the const canonicalisation
      expect(
        identical(const PyrxAttributeNull(), const PyrxAttributeNull()),
        isTrue,
      );
    });

    test('PyrxAttributeArr is deep-equal', () {
      final a = PyrxAttributeArr(const [
        PyrxAttributeInt64(1),
        PyrxAttributeStr('x'),
      ]);
      final b = PyrxAttributeArr(const [
        PyrxAttributeInt64(1),
        PyrxAttributeStr('x'),
      ]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      final c = PyrxAttributeArr(const [
        PyrxAttributeInt64(1),
        PyrxAttributeStr('y'),
      ]);
      expect(a, isNot(c));
    });

    test('PyrxAttributeObj equality is order-independent', () {
      final a = PyrxAttributeObj(const {
        'k1': PyrxAttributeStr('v1'),
        'k2': PyrxAttributeInt64(2),
      });
      final b = PyrxAttributeObj(const {
        'k2': PyrxAttributeInt64(2),
        'k1': PyrxAttributeStr('v1'),
      });
      expect(a, equals(b));
      expect(
        a.hashCode,
        equals(b.hashCode),
        reason: 'order-independent hashing required for set/map keys',
      );
    });

    test('different subtypes are never equal even with matching values', () {
      expect(
        const PyrxAttributeInt64(1),
        isNot(const PyrxAttributeStr('1')),
      );
      expect(
        const PyrxAttributeBool(true),
        isNot(const PyrxAttributeInt64(1)),
      );
    });
  });

  group('PyrxAttributeValue — unmodifiability', () {
    test('PyrxAttributeArr backing list rejects add', () {
      final v = PyrxAttributeArr(const [PyrxAttributeInt64(1)]);
      expect(
        () => v.value.add(const PyrxAttributeInt64(2)),
        throwsUnsupportedError,
      );
    });

    test('PyrxAttributeObj backing map rejects []=', () {
      final v = PyrxAttributeObj(const {'k': PyrxAttributeStr('v')});
      expect(
        () => v.value['k2'] = const PyrxAttributeStr('v2'),
        throwsUnsupportedError,
      );
    });
  });

  group('PyrxAttributeValue.mapFromJson', () {
    test('null raw → empty unmodifiable map', () {
      final out = PyrxAttributeValue.mapFromJson(null);
      expect(out, isEmpty);
      expect(
        () => out['k'] = const PyrxAttributeNull(),
        throwsUnsupportedError,
      );
    });

    test('empty raw → empty unmodifiable map', () {
      final out = PyrxAttributeValue.mapFromJson(<Object?, Object?>{});
      expect(out, isEmpty);
      expect(
        () => out['k'] = const PyrxAttributeNull(),
        throwsUnsupportedError,
      );
    });

    test('typed map of leaves is converted leaf-by-leaf', () {
      final out = PyrxAttributeValue.mapFromJson(<Object?, Object?>{
        'name': 'Trieu',
        'age': 32,
        'pro': true,
        'note': null,
      });
      expect(out['name'], const PyrxAttributeStr('Trieu'));
      expect(out['age'], const PyrxAttributeInt64(32));
      expect(out['pro'], const PyrxAttributeBool(true));
      expect(out['note'], const PyrxAttributeNull());
    });

    test('null key in raw map is coerced to empty string', () {
      final out = PyrxAttributeValue.mapFromJson(<Object?, Object?>{
        null: 1,
        'k': 2,
      });
      expect(out[''], const PyrxAttributeInt64(1));
      expect(out['k'], const PyrxAttributeInt64(2));
    });
  });

  group('PyrxAttributeValue — exhaustive switch compiles', () {
    test('every sealed leaf is reachable in a switch expression', () {
      // This test isn't asserting runtime behaviour primarily; the
      // value is that the switch below WOULD NOT COMPILE if a new
      // sealed leaf were added and not handled. That's the
      // exhaustiveness guarantee we want at the type level. Adding a
      // new PyrxAttribute* subclass without updating this switch
      // breaks the build — exactly the contract we want.
      const samples = <PyrxAttributeValue>[
        PyrxAttributeStr('s'),
        PyrxAttributeInt64(1),
        PyrxAttributeDbl(1.0),
        PyrxAttributeBool(true),
        PyrxAttributeNull(),
      ];
      final tags = samples.map(_tagOf).toList();
      expect(tags, ['str', 'int', 'dbl', 'bool', 'null']);

      final arr = PyrxAttributeArr(const [PyrxAttributeNull()]);
      final obj = PyrxAttributeObj(const {'k': PyrxAttributeNull()});
      expect(_tagOf(arr), 'arr');
      expect(_tagOf(obj), 'obj');
    });
  });

  group('PyrxAttributeValue — toString is informative (debug aid)', () {
    test('every leaf includes its variant name and value', () {
      expect(const PyrxAttributeStr('hi').toString(), 'PyrxAttributeStr(hi)');
      expect(const PyrxAttributeInt64(7).toString(), 'PyrxAttributeInt64(7)');
      expect(
          const PyrxAttributeBool(true).toString(), 'PyrxAttributeBool(true)');
      expect(const PyrxAttributeNull().toString(), 'PyrxAttributeNull()');
      expect(const PyrxAttributeDbl(1.5).toString(), 'PyrxAttributeDbl(1.5)');
    });
  });
}

/// Sealed-class exhaustive switch — used by the "exhaustive switch
/// compiles" test above. If we add a new PyrxAttribute* subclass
/// without updating this function, the analyzer flags it (and the
/// test file fails to compile), forcing a conscious decision.
String _tagOf(PyrxAttributeValue v) => switch (v) {
      PyrxAttributeStr() => 'str',
      PyrxAttributeInt64() => 'int',
      PyrxAttributeDbl() => 'dbl',
      PyrxAttributeBool() => 'bool',
      PyrxAttributeNull() => 'null',
      PyrxAttributeArr() => 'arr',
      PyrxAttributeObj() => 'obj',
    };
