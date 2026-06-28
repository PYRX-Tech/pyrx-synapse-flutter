// PushReceivedEvent — typed Dart wrapper for the Pigeon-generated
// PushReceivedEventDto.
//
// The wire DTO uses two map fields with very different semantics:
//
//   - `data`:      the arbitrary APNs/FCM userInfo dictionary. Stays
//                  loosely-typed (`Map<String, Object?>`) because we
//                  can't constrain what the sender attached. JSON
//                  primitives are decoded; nested shapes too.
//   - `pyrxAttrs`: Synapse-stamped metadata (push_log_id, tenant_id,
//                  template_id, etc.). Always a typed
//                  `Map<String, PyrxAttributeValue>` because it's
//                  emitted by the platform under our control.
//
// This asymmetry mirrors the native iOS / Android SDKs exactly.
//
// The `receivedAt` ISO-8601 string is parsed to a UTC [DateTime].

import 'package:meta/meta.dart';
import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

import '../pyrx_attribute_value.dart';

/// Push notification received in the foreground (warm-start delivery).
///
/// Distinct from a cold-start push: when the OS launches the app FROM
/// a push tap, a [PushReceivedColdStart] event fires instead (the
/// payload shape is identical; the discriminator is the wrapping
/// sealed class). See ADR-0005 §D4 for the dedup contract.
@immutable
class PushReceivedEvent {
  const PushReceivedEvent({
    required this.title,
    required this.body,
    required this.pushLogId,
    required this.data,
    required this.pyrxAttrs,
    required this.receivedAt,
  });

  /// APS / FCM alert title. Empty string for silent / data-only pushes.
  final String title;

  /// APS / FCM alert body. Empty string for silent / data-only pushes.
  final String body;

  /// Synapse-issued push log row identifier (matches `push_logs.id`).
  /// `null` for pushes that did not carry the `pyrx` namespace (legacy
  /// or cross-vendor passthrough).
  final String? pushLogId;

  /// Arbitrary custom data the sender attached. JSON-shaped values
  /// (`String`, `num`, `bool`, `null`, `List`, `Map`); deeply nested.
  ///
  /// This map is loosely-typed because the sender controls its shape;
  /// the SDK cannot constrain it. For the typed Synapse metadata, see
  /// [pyrxAttrs].
  final Map<String, Object?> data;

  /// Synapse-stamped delivery metadata. Always a typed
  /// `Map<String, PyrxAttributeValue>`; an empty map (NOT null) when
  /// the push did not carry a `pyrx_attrs` namespace.
  final Map<String, PyrxAttributeValue> pyrxAttrs;

  /// Wall-clock instant the SDK observed the delivery. Always UTC.
  final DateTime receivedAt;

  /// Wrap a Pigeon-generated [PushReceivedEventDto].
  ///
  /// `data` keys are flattened from `Map<String?, Object?>` (Pigeon's
  /// wire shape) into `Map<String, Object?>` — null keys are coerced
  /// to the empty string. `pyrxAttrs` is run through
  /// [PyrxAttributeValue.mapFromJson] to restore typed pattern-matching.
  /// `receivedAt` is parsed; parse failure throws [FormatException].
  factory PushReceivedEvent.fromDto(PushReceivedEventDto dto) {
    return PushReceivedEvent(
      title: dto.title,
      body: dto.body,
      pushLogId: dto.pushLogId,
      data: _stringKeyedMap(dto.data),
      pyrxAttrs: PyrxAttributeValue.mapFromJson(dto.pyrxAttrs),
      receivedAt: DateTime.parse(dto.receivedAt).toUtc(),
    );
  }

  /// Flatten Pigeon's `Map<String?, Object?>` to a `Map<String, Object?>`.
  /// Null keys are coerced to the empty string — defensive, real APNs/
  /// FCM payloads never produce null keys.
  static Map<String, Object?> _stringKeyedMap(Map<Object?, Object?> raw) {
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key is String
          ? entry.key as String
          : entry.key?.toString() ?? '';
      out[key] = entry.value;
    }
    return Map<String, Object?>.unmodifiable(out);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PushReceivedEvent) return false;
    if (other.title != title) return false;
    if (other.body != body) return false;
    if (other.pushLogId != pushLogId) return false;
    if (other.receivedAt != receivedAt) return false;
    if (!_mapEqual(other.data, data)) return false;
    if (!_attrMapEqual(other.pyrxAttrs, pyrxAttrs)) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
        title,
        body,
        pushLogId,
        receivedAt,
        // Map hashes are length-based to keep equality + hashCode
        // contract honest without forcing a deep-walk on every lookup;
        // a real collision is acceptable here (the hash is just a
        // bucket hint — equality runs the deep compare).
        data.length,
        pyrxAttrs.length,
      );

  @override
  String toString() {
    return 'PushReceivedEvent('
        'title: $title, '
        'body: $body, '
        'pushLogId: $pushLogId, '
        'data: $data, '
        'pyrxAttrs: $pyrxAttrs, '
        'receivedAt: $receivedAt'
        ')';
  }
}

/// Shallow + recursive map equality. Used by [PushReceivedEvent.==]
/// for the loosely-typed `data` field where values may themselves be
/// nested maps or lists.
bool _mapEqual(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (!_valueEqual(entry.value, b[entry.key])) return false;
  }
  return true;
}

bool _valueEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_valueEqual(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_valueEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

bool _attrMapEqual(
  Map<String, PyrxAttributeValue> a,
  Map<String, PyrxAttributeValue> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
