// PyrxEventStreamHandler.swift
// pyrx_synapse_ios — bridges `Pyrx.shared.events()` (AsyncStream) into the
// Pigeon-generated `StreamEventsStreamHandler` that Flutter's EventChannel
// machinery routes through.
//
// Lifecycle
// ---------
// Pigeon calls `onListen(withArguments:sink:)` when the first Dart
// subscriber attaches (Flutter's `EventChannel.receiveBroadcastStream()`
// triggers it lazily). We launch a single Task that iterates
// `Pyrx.shared.events()` — an AsyncStream from PYRXSynapse 0.1.2's
// observer surface (Phase 9.2.1) — and forwards every native PyrxEvent
// case into the Pigeon-typed `PyrxEventEnvelope` wire shape.
//
// Pigeon calls `onCancel(withArguments:)` when the last Dart subscriber
// detaches. We cancel the held Task; the AsyncStream's continuation
// terminates and the native observer registry GCs the subscription.
//
// Why one native subscription for any number of Dart subscribers: Flutter's
// EventChannel multiplexes multiple Dart listeners on top of a single
// native StreamHandler. Subscribing N times would create N AsyncStreams
// from the native SDK and duplicate-deliver each event. The lazy
// subscribe-on-first / cancel-on-last pattern keeps overhead at zero when
// no Dart subscriber is attached.
//
// Late-subscriber replay (cold-start race window) is native-side per
// Phase 9.2.1 PR-3: PYRXSynapse 0.1.2 buffers the most recent 4 events
// per `events()` call. A Dart subscriber that attaches after a
// cold-start `pushReceivedColdStart` event has fired still receives the
// buffered event on its first read.

import Flutter
import Foundation
import PYRXSynapse

final class PyrxEventStreamHandler: StreamEventsStreamHandler {

  /// The native observer subscription. Held across `onListen` /
  /// `onCancel` so we can cancel it on detach. Single-element optional —
  /// re-entrant `onListen` (Flutter sometimes calls it twice on warm
  /// reload) is guarded by cancelling-then-restarting.
  private var observerTask: Task<Void, Never>?

  override func onListen(
    withArguments arguments: Any?,
    sink: PigeonEventSink<PyrxEventEnvelope>
  ) {
    observerTask?.cancel()
    observerTask = Task { [weak self] in
      // `Pyrx.shared.events()` is an AsyncStream that survives until
      // cancelled. Each iteration yields one `PyrxEvent` from the
      // closed taxonomy fixed in Phase 9.2.1.
      for await event in Pyrx.shared.events() {
        guard self != nil else { return }
        if Task.isCancelled { return }
        let envelope = Self.encode(event)
        sink.success(envelope)
      }
    }
  }

  override func onCancel(withArguments arguments: Any?) {
    observerTask?.cancel()
    observerTask = nil
  }

  // MARK: - Native → Wire conversion

  private static func encode(_ event: PyrxEvent) -> PyrxEventEnvelope {
    switch event {
    case let .pushReceived(payload):
      return PyrxEventEnvelope(
        kind: .pushReceived,
        pushReceived: encodePushReceived(payload)
      )
    case let .pushClicked(payload):
      return PyrxEventEnvelope(
        kind: .pushClicked,
        pushClicked: encodePushClicked(payload)
      )
    case let .pushReceivedColdStart(payload):
      return PyrxEventEnvelope(
        kind: .pushReceivedColdStart,
        pushReceivedColdStart: encodePushReceived(payload)
      )
    case let .queueDrained(count):
      return PyrxEventEnvelope(
        kind: .queueDrained,
        queueDrained: QueueDrainedEventDto(count: Int64(count))
      )
    case let .identityChanged(before, after):
      return PyrxEventEnvelope(
        kind: .identityChanged,
        identityChanged: IdentityChangedEventDto(
          before: encodeIdentity(before),
          after: encodeIdentity(after)
        )
      )
    case let .inAppMessageReceived(message):
      // Phase 10 PR-2b — the in-app fire-point on the native observer
      // stream. The umbrella's `_ShowRegistry` re-dispatches by
      // placement; here we just pack the message into the envelope.
      return PyrxEventEnvelope(
        kind: .inAppMessageReceived,
        inAppMessageReceived: InAppMessageReceivedEventDto(
          message: PyrxSynapseHostApiImpl.encodeInAppMessage(message)
        )
      )
    case let .inAppMessageDismissed(messageId, reason):
      return PyrxEventEnvelope(
        kind: .inAppMessageDismissed,
        inAppMessageDismissed: InAppMessageDismissedEventDto(
          messageId: messageId,
          reason: reason
        )
      )
    }
  }

  private static func encodePushReceived(_ p: PushReceivedEvent) -> PushReceivedEventDto {
    return PushReceivedEventDto(
      title: p.title,
      body: p.body,
      pushLogId: p.pushLogId?.uuidString,
      data: stringKeyed(p.userInfo),
      pyrxAttrs: p.pyrxAttributes.map(encodeAttributeMap),
      receivedAt: Self.iso8601.string(from: p.receivedAt)
    )
  }

  private static func encodePushClicked(_ p: PushClickedEvent) -> PushClickedEventDto {
    return PushClickedEventDto(
      pushLogId: p.pushLogId?.uuidString,
      deepLink: p.deepLink?.absoluteString,
      actionId: p.actionId,
      pyrxAttrs: p.pyrxAttributes.map(encodeAttributeMap),
      clickedAt: Self.iso8601.string(from: p.clickedAt)
    )
  }

  private static func encodeIdentity(_ s: IdentitySnapshot) -> IdentitySnapshotDto {
    return IdentitySnapshotDto(
      anonymousId: s.anonymousId,
      externalId: s.externalId,
      snapshotAt: Self.iso8601.string(from: s.snapshotAt)
    )
  }

  /// Convert PYRXSynapse's typed `[String: PyrxAttributeValue]` into the
  /// JSON-friendly `[String: Any]` Pigeon's standard codec accepts. The
  /// app-facing Dart layer (PR-2) re-wraps these into the typed
  /// `PyrxAttributeValue` Dart sealed class.
  private static func encodeAttributeMap(_ map: [String: PyrxAttributeValue]) -> [String?: Any?] {
    var out: [String?: Any?] = [:]
    for (k, v) in map {
      out[k] = encodeAttribute(v)
    }
    return out
  }

  private static func encodeAttribute(_ value: PyrxAttributeValue) -> Any {
    switch value {
    case .null:
      return NSNull()
    case let .string(s):
      return s
    case let .int(i):
      return i
    case let .double(d):
      return d
    case let .bool(b):
      return b
    case let .array(arr):
      return arr.map { encodeAttribute($0) }
    case let .object(obj):
      var dict: [String: Any] = [:]
      for (k, v) in obj { dict[k] = encodeAttribute(v) }
      return dict
    }
  }

  /// Convert `[AnyHashable: Any]` (the APNs userInfo dictionary shape)
  /// into the `[String?: Any?]` Pigeon Map codec expects. Non-String
  /// keys are coerced via `String(describing:)`; values pass through.
  private static func stringKeyed(_ src: [AnyHashable: Any]) -> [String?: Any?] {
    var out: [String?: Any?] = [:]
    for (k, v) in src {
      let key = (k as? String) ?? String(describing: k)
      out[key] = v
    }
    return out
  }

  private static let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
}
