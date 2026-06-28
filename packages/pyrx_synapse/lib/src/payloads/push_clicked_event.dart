// PushClickedEvent — typed Dart wrapper for the Pigeon-generated
// PushClickedEventDto.
//
// Fires for warm-start taps only. Cold-start taps (where the app was
// launched FROM the tap) publish [PushReceivedColdStart] instead.
// The dedup invariant is enforced native-side via a 5-second
// `push_log_id` LRU — see ADR-0005 §D4.

import 'package:meta/meta.dart';
import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

import '../pyrx_attribute_value.dart';

/// User tapped a delivered push notification (warm-start).
///
/// Mutually exclusive with [PushReceivedColdStart] for the same push
/// tap: native-side dedup guarantees exactly one of the two fires per
/// real tap. Apps can treat the pair "{PushClicked OR
/// PushReceivedColdStart}" as the canonical "user-actioned a push"
/// signal.
@immutable
class PushClickedEvent {
  const PushClickedEvent({
    required this.pushLogId,
    required this.deepLink,
    required this.actionId,
    required this.pyrxAttrs,
    required this.clickedAt,
  });

  /// Synapse-issued push log row identifier (matches `push_logs.id`).
  /// `null` for non-Synapse pushes (legacy passthrough).
  final String? pushLogId;

  /// Optional deep link the sender attached. Caller is responsible for
  /// validating + routing — the SDK does NOT auto-navigate. `null`
  /// when no link was set on the push.
  final String? deepLink;

  /// Action identifier for taps on a notification action button
  /// (iOS `UNNotificationAction`, Android notification action). `null`
  /// for plain body taps.
  final String? actionId;

  /// Synapse-stamped delivery metadata. Always a typed
  /// `Map<String, PyrxAttributeValue>`; an empty map when the push did
  /// not carry a `pyrx_attrs` namespace.
  final Map<String, PyrxAttributeValue> pyrxAttrs;

  /// Wall-clock instant the SDK observed the tap. Always UTC.
  final DateTime clickedAt;

  /// Wrap a Pigeon-generated [PushClickedEventDto].
  ///
  /// `pyrxAttrs` is run through [PyrxAttributeValue.mapFromJson] to
  /// restore typed pattern-matching. `clickedAt` is parsed; parse
  /// failure throws [FormatException].
  factory PushClickedEvent.fromDto(PushClickedEventDto dto) {
    return PushClickedEvent(
      pushLogId: dto.pushLogId,
      deepLink: dto.deepLink,
      actionId: dto.actionId,
      pyrxAttrs: PyrxAttributeValue.mapFromJson(dto.pyrxAttrs),
      clickedAt: DateTime.parse(dto.clickedAt).toUtc(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PushClickedEvent) return false;
    if (other.pushLogId != pushLogId) return false;
    if (other.deepLink != deepLink) return false;
    if (other.actionId != actionId) return false;
    if (other.clickedAt != clickedAt) return false;
    if (other.pyrxAttrs.length != pyrxAttrs.length) return false;
    for (final entry in pyrxAttrs.entries) {
      if (!other.pyrxAttrs.containsKey(entry.key)) return false;
      if (other.pyrxAttrs[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        pushLogId,
        deepLink,
        actionId,
        clickedAt,
        pyrxAttrs.length,
      );

  @override
  String toString() {
    return 'PushClickedEvent('
        'pushLogId: $pushLogId, '
        'deepLink: $deepLink, '
        'actionId: $actionId, '
        'pyrxAttrs: $pyrxAttrs, '
        'clickedAt: $clickedAt'
        ')';
  }
}
