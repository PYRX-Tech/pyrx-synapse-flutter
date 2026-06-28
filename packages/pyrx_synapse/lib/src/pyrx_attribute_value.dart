// PyrxAttributeValue — Dart sealed sum mirroring the native typed
// attribute value used in push payloads.
//
// On the wire, `pyrx_attrs` crosses the Pigeon bridge as
// `Map<String?, Object?>` (the standard codec's loosest JSON-shaped
// map). On the native side it is a strongly-typed sum:
//
//   iOS     — `PyrxAttributeValue` (PYRXSynapse 0.1.2)
//   Android — `PyrxAttributeValue` sealed class (synapse-core 0.1.4)
//
// This Dart sealed class restores that typing on the Flutter side so
// app code can pattern-match exhaustively instead of poking at
// `Object?` and downcasting. The class is consumed by the typed
// payload data classes ([PushReceivedEvent], [PushClickedEvent]) the
// umbrella exposes through the merged `Stream<PyrxEvent>`.
//
// Placement note
// --------------
// Phase 9.3 PR-2's brief originally proposed putting this in
// `pyrx_synapse_platform_interface`. We kept it in the umbrella
// package instead because:
//
//   1. It is app-facing typed sugar — the wire itself stays as
//      JSON-shaped `Map<String?, Object?>`. The platform-interface
//      package's job is the platform contract, not consumer
//      ergonomics.
//   2. The payload data classes that consume it ([PushReceivedEvent],
//      [PushClickedEvent]) live in the umbrella as well — co-locating
//      avoids a circular-feel between "wrapper types live there" and
//      "their atoms live here".
//   3. A future `pyrx_synapse_web` platform package doesn't need this
//      type — it would emit its own envelope and the umbrella would
//      wrap the same way.
//
// Subtype shape (chosen idiom)
// ----------------------------
// Dart sealed classes work cleanly with `final class` leaves. We use a
// single-letter-prefixed subtype name (`PyrxAttribute*`) instead of
// nesting (`PyrxAttributeValue.Str`) because:
//
//   - Pattern destructuring reads naturally: `PyrxAttributeStr(:final value)`
//   - Nested classes can't have unnamed constructors that participate
//     in sealed-class exhaustiveness without `static` factory shims
//   - The `PyrxAttribute` prefix prevents clashes with Dart's core
//     `String`, `int`, `double`, `bool`, `List`, `Map` names in
//     consumer scopes.

import 'package:meta/meta.dart';

/// A strongly-typed value inside a push notification's `pyrx_attrs` map.
///
/// One of seven leaf types:
///
/// - [PyrxAttributeStr]   — wraps a `String`
/// - [PyrxAttributeInt64] — wraps a 64-bit `int`
/// - [PyrxAttributeDbl]   — wraps a `double` (incl. NaN / infinities)
/// - [PyrxAttributeBool]  — wraps a `bool`
/// - [PyrxAttributeNull]  — represents an explicit `null` slot (NOT a
///   missing key)
/// - [PyrxAttributeArr]   — wraps a `List<PyrxAttributeValue>`
/// - [PyrxAttributeObj]   — wraps a `Map<String, PyrxAttributeValue>`
///
/// Exhaustive `switch` is enforced by the `sealed` modifier — Dart
/// 3.x requires every case to be handled (or a wildcard `_`) at
/// compile time:
///
/// ```dart
/// String summarise(PyrxAttributeValue v) => switch (v) {
///   PyrxAttributeStr(:final value)   => 'str: $value',
///   PyrxAttributeInt64(:final value) => 'int: $value',
///   PyrxAttributeDbl(:final value)   => 'dbl: $value',
///   PyrxAttributeBool(:final value)  => 'bool: $value',
///   PyrxAttributeNull()              => 'null',
///   PyrxAttributeArr(:final value)   => 'arr(${value.length})',
///   PyrxAttributeObj(:final value)   => 'obj(${value.length})',
/// };
/// ```
///
/// Construct from the JSON-shaped `Object?` Pigeon emits via
/// [PyrxAttributeValue.fromJson]; serialise back via [toJson]. The
/// pair is round-trip stable for every JSON-representable shape.
@immutable
sealed class PyrxAttributeValue {
  const PyrxAttributeValue();

  /// Build a typed [PyrxAttributeValue] from the loose `Object?` the
  /// Pigeon codec emits for `Map<String?, Object?>` slots.
  ///
  /// Wire-shape rules:
  ///
  /// - `null` → [PyrxAttributeNull] singleton
  /// - `String` → [PyrxAttributeStr]
  /// - `bool` → [PyrxAttributeBool]
  /// - `int` → [PyrxAttributeInt64]
  /// - `double` → [PyrxAttributeDbl]
  /// - `List` → [PyrxAttributeArr], elements recursively converted
  /// - `Map` → [PyrxAttributeObj], keys must be `String` (non-String
  ///   keys are coerced via `toString()`), values recursively converted
  ///
  /// Any other runtime type throws [ArgumentError]. This is a loud
  /// failure mode on purpose — silently dropping unknown types
  /// would mask native-side wire-format drift.
  factory PyrxAttributeValue.fromJson(Object? raw) {
    if (raw == null) {
      return const PyrxAttributeNull();
    }
    if (raw is String) {
      return PyrxAttributeStr(raw);
    }
    if (raw is bool) {
      return PyrxAttributeBool(raw);
    }
    if (raw is int) {
      return PyrxAttributeInt64(raw);
    }
    if (raw is double) {
      return PyrxAttributeDbl(raw);
    }
    if (raw is List) {
      return PyrxAttributeArr(
        List<PyrxAttributeValue>.unmodifiable(
          raw.map<PyrxAttributeValue>(PyrxAttributeValue.fromJson),
        ),
      );
    }
    if (raw is Map) {
      final out = <String, PyrxAttributeValue>{};
      for (final entry in raw.entries) {
        // Pigeon's `Map<String?, Object?>` permits null keys; we
        // coerce to the empty string (matching iOS/Android's
        // `String(describing:)` fallback). Real APNs/FCM payloads
        // never produce null keys, so this branch is defensive only.
        final key = entry.key is String
            ? entry.key as String
            : entry.key?.toString() ?? '';
        out[key] = PyrxAttributeValue.fromJson(entry.value);
      }
      return PyrxAttributeObj(
          Map<String, PyrxAttributeValue>.unmodifiable(out));
    }
    throw ArgumentError.value(
      raw,
      'raw',
      'PyrxAttributeValue.fromJson cannot convert ${raw.runtimeType}; '
          'expected null / String / bool / int / double / List / Map',
    );
  }

  /// Convenience: convert a Pigeon-shaped `Map<String?, Object?>` (or
  /// `null`) into a typed `Map<String, PyrxAttributeValue>`. Returns
  /// an empty unmodifiable map for `null` input. Used by the payload
  /// data classes to wrap `pyrxAttrs` slots.
  static Map<String, PyrxAttributeValue> mapFromJson(
    Map<Object?, Object?>? raw,
  ) {
    if (raw == null) {
      return const <String, PyrxAttributeValue>{};
    }
    final out = <String, PyrxAttributeValue>{};
    for (final entry in raw.entries) {
      final key = entry.key is String
          ? entry.key as String
          : entry.key?.toString() ?? '';
      out[key] = PyrxAttributeValue.fromJson(entry.value);
    }
    return Map<String, PyrxAttributeValue>.unmodifiable(out);
  }

  /// Serialise back to the JSON-shaped `Object?` Pigeon accepts.
  ///
  /// Round-trip identity: for every JSON-representable Dart value `v`,
  /// `PyrxAttributeValue.fromJson(v).toJson()` is `==`-equal to `v`
  /// (modulo `Map` key types — output keys are always `String`).
  Object? toJson();
}

/// A `String` attribute value.
final class PyrxAttributeStr extends PyrxAttributeValue {
  const PyrxAttributeStr(this.value);

  final String value;

  @override
  Object? toJson() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PyrxAttributeStr && other.value == value;

  @override
  int get hashCode => Object.hash(PyrxAttributeStr, value);

  @override
  String toString() => 'PyrxAttributeStr($value)';
}

/// An integer attribute value (64-bit on both target platforms).
final class PyrxAttributeInt64 extends PyrxAttributeValue {
  const PyrxAttributeInt64(this.value);

  final int value;

  @override
  Object? toJson() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PyrxAttributeInt64 && other.value == value;

  @override
  int get hashCode => Object.hash(PyrxAttributeInt64, value);

  @override
  String toString() => 'PyrxAttributeInt64($value)';
}

/// A floating-point attribute value. NaN and ±infinity are preserved.
final class PyrxAttributeDbl extends PyrxAttributeValue {
  const PyrxAttributeDbl(this.value);

  final double value;

  @override
  Object? toJson() => value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PyrxAttributeDbl) return false;
    // NaN-aware equality: two NaNs are considered equal so that
    // round-tripping a NaN-bearing payload produces a stable
    // comparison. Without this, fromJson(d).toJson() == d would fail
    // for NaN inputs.
    if (value.isNaN && other.value.isNaN) return true;
    return other.value == value;
  }

  @override
  int get hashCode {
    // Normalise NaN to a single canonical hash so all NaN-bearing
    // instances collide in maps and sets, matching the operator ==
    // contract above.
    if (value.isNaN) return Object.hash(PyrxAttributeDbl, double.nan.hashCode);
    return Object.hash(PyrxAttributeDbl, value);
  }

  @override
  String toString() => 'PyrxAttributeDbl($value)';
}

/// A boolean attribute value.
final class PyrxAttributeBool extends PyrxAttributeValue {
  const PyrxAttributeBool(this.value);

  final bool value;

  @override
  Object? toJson() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PyrxAttributeBool && other.value == value;

  @override
  int get hashCode => Object.hash(PyrxAttributeBool, value);

  @override
  String toString() => 'PyrxAttributeBool($value)';
}

/// An explicit `null` attribute slot (distinct from "key missing").
///
/// Singleton — every `null` deserialises to the same instance, so
/// reference equality is also true equality.
final class PyrxAttributeNull extends PyrxAttributeValue {
  const PyrxAttributeNull();

  @override
  Object? toJson() => null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PyrxAttributeNull;

  @override
  int get hashCode => (PyrxAttributeNull).hashCode;

  @override
  String toString() => 'PyrxAttributeNull()';
}

/// An ordered list of attribute values. The backing list is
/// unmodifiable; consumers that need to mutate should copy.
final class PyrxAttributeArr extends PyrxAttributeValue {
  PyrxAttributeArr(List<PyrxAttributeValue> value)
      : value = List<PyrxAttributeValue>.unmodifiable(value);

  final List<PyrxAttributeValue> value;

  @override
  Object? toJson() => value.map((e) => e.toJson()).toList(growable: false);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PyrxAttributeArr) return false;
    if (other.value.length != value.length) return false;
    for (var i = 0; i < value.length; i++) {
      if (value[i] != other.value[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(PyrxAttributeArr, Object.hashAll(value));

  @override
  String toString() => 'PyrxAttributeArr($value)';
}

/// A string-keyed map of attribute values. The backing map is
/// unmodifiable.
final class PyrxAttributeObj extends PyrxAttributeValue {
  PyrxAttributeObj(Map<String, PyrxAttributeValue> value)
      : value = Map<String, PyrxAttributeValue>.unmodifiable(value);

  final Map<String, PyrxAttributeValue> value;

  @override
  Object? toJson() => value.map((k, v) => MapEntry(k, v.toJson()));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PyrxAttributeObj) return false;
    if (other.value.length != value.length) return false;
    for (final entry in value.entries) {
      if (!other.value.containsKey(entry.key)) return false;
      if (other.value[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    // Order-independent hash so two semantically-equal maps hash the
    // same regardless of insertion order. Dart's hashAllUnordered is
    // exactly this contract.
    final entryHashes = value.entries.map(
      (e) => Object.hash(e.key, e.value),
    );
    return Object.hash(PyrxAttributeObj, Object.hashAllUnordered(entryHashes));
  }

  @override
  String toString() => 'PyrxAttributeObj($value)';
}
