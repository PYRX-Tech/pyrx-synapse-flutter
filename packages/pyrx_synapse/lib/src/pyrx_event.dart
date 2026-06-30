// PyrxEvent — Dart sealed class hierarchy for the 5-event observer
// surface fixed in Phase 9.2.1 (ADR-0005).
//
// The native side publishes 5 event variants from a single observer
// stream (iOS `AsyncStream<PyrxEvent>` in PYRXSynapse 0.1.2; Android
// `SharedFlow<PyrxEvent>` in synapse-core 0.1.4). The Pigeon spec
// (PR-1) collapses them into a single discriminated envelope
// (`PyrxEventEnvelope` + `PyrxEventKind`) because Pigeon's standard
// codec doesn't ship cross-language sealed-class generation.
//
// This file re-expands the envelope into a Dart sealed `PyrxEvent`
// hierarchy so consumers get exhaustive `switch` ergonomics at compile
// time:
//
//   final summary = switch (event) {
//     PushReceived(:final event)         => 'fg: ${event.title}',
//     PushClicked(:final event)          => 'tap: ${event.deepLink}',
//     PushReceivedColdStart(:final event)=> 'cold: ${event.title}',
//     QueueDrained(:final count)         => 'flushed $count',
//     IdentityChanged(:final after)      => 'now: ${after.externalId}',
//   };
//
// Each leaf is `final class` — apps cannot subclass them. The closed
// hierarchy is the Phase 9.2.1 taxonomy contract; adding a new variant
// requires native-SDK work in PYRXSynapse / synapse-core first.
//
// The bridge-to-sealed mapping (envelope discriminator → sealed leaf)
// lives in [PyrxEvent.fromEnvelope]. The Synapse namespace's merged
// stream applies it; consumers never see the envelope.

import 'package:meta/meta.dart';
import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

import 'payloads/payloads.dart';

/// Base type for every event the SDK publishes on
/// `Synapse.events`. Closed sum — exactly one of:
///
/// - [PushReceived]            — foreground push delivery
/// - [PushClicked]             — warm-start push tap
/// - [PushReceivedColdStart]   — cold-start push (app launched FROM tap)
/// - [QueueDrained]            — internal event queue flushed
/// - [IdentityChanged]         — identify / alias / logout completed
/// - [InAppMessageReceived]    — a fresh in-app message arrived (Phase 10 PR-2b)
/// - [InAppMessageDismissed]   — an in-app message was dismissed   (Phase 10 PR-2b)
///
/// Use `switch` for exhaustive pattern matching; the compiler will
/// flag any new variant (none expected without a native-side change)
/// the consumer forgets to handle.
@immutable
sealed class PyrxEvent {
  const PyrxEvent();

  /// Decode the Pigeon-shaped [PyrxEventEnvelope] into the typed
  /// sealed leaf. Returns `null` for envelope kinds that don't have a
  /// matching Dart leaf yet — by design, so a future-compatible
  /// native SDK that adds an 8th `PyrxEventKind` case won't crash
  /// older Flutter consumers. The merged stream in [Synapse.events]
  /// silently drops `null` returns so apps don't see undecodable
  /// events.
  ///
  /// Throws [StateError] when the envelope's `kind` discriminator
  /// disagrees with which `*Payload` slot is populated — that's a
  /// wire-contract violation from the native bridge, NOT a forward-
  /// compatibility concern.
  static PyrxEvent? fromEnvelope(PyrxEventEnvelope envelope) {
    switch (envelope.kind) {
      case PyrxEventKind.pushReceived:
        final dto = envelope.pushReceived;
        if (dto == null) {
          throw StateError(
            'PyrxEventEnvelope.kind=pushReceived but pushReceived is null',
          );
        }
        return PushReceived(PushReceivedEvent.fromDto(dto));

      case PyrxEventKind.pushClicked:
        final dto = envelope.pushClicked;
        if (dto == null) {
          throw StateError(
            'PyrxEventEnvelope.kind=pushClicked but pushClicked is null',
          );
        }
        return PushClicked(PushClickedEvent.fromDto(dto));

      case PyrxEventKind.pushReceivedColdStart:
        final dto = envelope.pushReceivedColdStart;
        if (dto == null) {
          throw StateError(
            'PyrxEventEnvelope.kind=pushReceivedColdStart but '
            'pushReceivedColdStart is null',
          );
        }
        return PushReceivedColdStart(PushReceivedEvent.fromDto(dto));

      case PyrxEventKind.queueDrained:
        final dto = envelope.queueDrained;
        if (dto == null) {
          throw StateError(
            'PyrxEventEnvelope.kind=queueDrained but queueDrained is null',
          );
        }
        return QueueDrained(dto.count);

      case PyrxEventKind.identityChanged:
        final dto = envelope.identityChanged;
        if (dto == null) {
          throw StateError(
            'PyrxEventEnvelope.kind=identityChanged but '
            'identityChanged is null',
          );
        }
        return IdentityChanged(
          before:
              dto.before == null ? null : IdentitySnapshot.fromDto(dto.before!),
          after: IdentitySnapshot.fromDto(dto.after),
        );

      case PyrxEventKind.inAppMessageReceived:
        final dto = envelope.inAppMessageReceived;
        if (dto == null) {
          throw StateError(
            'PyrxEventEnvelope.kind=inAppMessageReceived but '
            'inAppMessageReceived is null',
          );
        }
        return InAppMessageReceived(InAppMessage.fromDto(dto.message));

      case PyrxEventKind.inAppMessageDismissed:
        final dto = envelope.inAppMessageDismissed;
        if (dto == null) {
          throw StateError(
            'PyrxEventEnvelope.kind=inAppMessageDismissed but '
            'inAppMessageDismissed is null',
          );
        }
        return InAppMessageDismissed(
          messageId: dto.messageId,
          reason: dto.reason,
        );
    }
  }
}

/// Push notification delivered to the foreground (warm-start).
///
/// Pattern: `PushReceived(:final event)` extracts the [PushReceivedEvent]
/// payload directly.
final class PushReceived extends PyrxEvent {
  const PushReceived(this.event);

  final PushReceivedEvent event;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PushReceived && other.event == event;

  @override
  int get hashCode => Object.hash(PushReceived, event);

  @override
  String toString() => 'PushReceived($event)';
}

/// User tapped a push notification while the app was already running
/// (warm-start). Mutually exclusive with [PushReceivedColdStart] for
/// the same tap.
final class PushClicked extends PyrxEvent {
  const PushClicked(this.event);

  final PushClickedEvent event;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PushClicked && other.event == event;

  @override
  int get hashCode => Object.hash(PushClicked, event);

  @override
  String toString() => 'PushClicked($event)';
}

/// App was launched FROM a push tap (cold start). Carries the same
/// [PushReceivedEvent] payload shape as [PushReceived] — the
/// distinguishing signal is the wrapping type, not a payload field.
///
/// Late-subscriber replay (the cold-start race) is handled native-side:
/// PYRXSynapse 0.1.2 / synapse-core 0.1.4 buffer the most recent 4
/// events per observer stream, so a Dart subscriber that attaches a
/// few hundred milliseconds after the OS-driven cold-start still
/// receives this event.
final class PushReceivedColdStart extends PyrxEvent {
  const PushReceivedColdStart(this.event);

  final PushReceivedEvent event;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushReceivedColdStart && other.event == event;

  @override
  int get hashCode => Object.hash(PushReceivedColdStart, event);

  @override
  String toString() => 'PushReceivedColdStart($event)';
}

/// Internal event queue successfully flushed [count] events to the
/// Synapse backend. Debug-only — most apps will never subscribe.
/// Does NOT fire on no-op drain passes (zero events to send).
final class QueueDrained extends PyrxEvent {
  const QueueDrained(this.count);

  /// Number of events flushed in this drain cycle. Always > 0.
  final int count;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is QueueDrained && other.count == count;

  @override
  int get hashCode => Object.hash(QueueDrained, count);

  @override
  String toString() => 'QueueDrained($count)';
}

/// SDK's resolved identity transitioned via identify / alias / logout.
///
/// [before] is `null` only on the very first identify after a fresh
/// install (no prior identity state recorded). Otherwise both
/// snapshots are non-null.
///
/// Transition detection:
///
/// - **Login**:  `before?.externalId == null && after.externalId != null`
/// - **Logout**: `before?.externalId != null && after.externalId == null`
/// - **Switch**: both non-null AND `before.externalId != after.externalId`
final class IdentityChanged extends PyrxEvent {
  const IdentityChanged({required this.before, required this.after});

  /// Prior identity state. `null` only on the very first identify
  /// after a fresh install.
  final IdentitySnapshot? before;

  /// Resolved identity state after the transition. Always non-null.
  final IdentitySnapshot after;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IdentityChanged &&
        other.before == before &&
        other.after == after;
  }

  @override
  int get hashCode => Object.hash(IdentityChanged, before, after);

  @override
  String toString() => 'IdentityChanged(before: $before, after: $after)';
}

/// Phase 10 PR-2b — a new in-app message arrived in the SDK's cache and
/// is about to be dispatched to a registered render callback.
///
/// Fires ONCE per assignment id — the SDK dedupes by [InAppMessage.id]
/// so re-polling the same eligible message does NOT re-fire. Identity
/// switch (`identify` to a different external id) clears the dedupe
/// set native-side so the new contact's messages get fresh emissions.
///
/// Fires BEFORE the per-placement render callback runs so analytics
/// middleware can observe every in-app message globally without
/// registering a callback for every placement.
///
/// Symmetric with the browser SDK's `inAppMessageReceived` observer
/// event and the iOS / Android SDK's equivalents per ADR-0009 D5.
final class InAppMessageReceived extends PyrxEvent {
  const InAppMessageReceived(this.message);

  final InAppMessage message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InAppMessageReceived && other.message == message;

  @override
  int get hashCode => Object.hash(InAppMessageReceived, message);

  @override
  String toString() => 'InAppMessageReceived($message)';
}

/// Phase 10 PR-2b — an in-app message was dismissed.
///
/// Fires once per [Synapse.inApp.dismiss] call (host-initiated). Reserved
/// for forward-compat with future expiry-driven auto-dismiss.
///
/// [reason] is the host-supplied free-form string (e.g.
/// `"user_dismissed"`, `"cta_dismissed"`, `"expired"`). It is NOT
/// crossed to the backend today — the PR-1 `/v1/in-app/log` schema
/// does not carry it — but observers receive it for analytics.
///
/// Symmetric with the browser SDK's `inAppMessageDismissed` observer
/// event per ADR-0009 D5.
final class InAppMessageDismissed extends PyrxEvent {
  const InAppMessageDismissed({required this.messageId, required this.reason});

  /// The assignment id ([InAppMessage.id]) of the dismissed message.
  /// Note: when [Synapse.inApp.dismiss] is called with an unknown id,
  /// the SDK still emits this event — the observer matches the call
  /// semantics, not the cache state.
  final String messageId;

  /// Host-supplied free-form reason. The SDK does NOT validate or
  /// interpret it.
  final String? reason;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InAppMessageDismissed &&
        other.messageId == messageId &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(InAppMessageDismissed, messageId, reason);

  @override
  String toString() =>
      'InAppMessageDismissed(messageId: $messageId, reason: $reason)';
}
