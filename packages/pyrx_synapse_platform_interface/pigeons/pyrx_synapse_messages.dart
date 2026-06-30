// SPDX-License-Identifier: MIT
//
// Pigeon spec for the PYRX Synapse Flutter SDK.
//
// This is the SINGLE SOURCE OF TRUTH for the type-safe MethodChannel +
// EventChannel layer between Dart and the iOS / Android native SDKs.
// Pigeon generates three artifacts from this file:
//
//   - lib/src/generated/pyrx_synapse_messages.g.dart   (Dart side)
//   - ../pyrx_synapse_ios/ios/Classes/Messages.g.swift (Swift side)
//   - ../pyrx_synapse_android/android/src/main/kotlin/tech/pyrx/synapse/flutter/generated/Messages.g.kt (Kotlin side)
//
// To regenerate (after editing this file), run from the repo root:
//
//   melos run pigeon-generate
//
// The generated files are committed. CI runs `melos run pigeon-check` to
// guarantee parity between this spec and the committed outputs.
//
// Design references:
//   - Phase 9.3 plan §1 D4 (Pigeon over raw MethodChannel)
//     ../../../../pyrx.synapse/docs/plans/phase-9.3-flutter-sdk-plan-2026-06-27.md
//   - Phase 9.2.1 plan (the 5-event observer surface this Pigeon spec wraps)
//   - The published native SDK public surfaces:
//       iOS:     pyrx-synapse-ios/Sources/PYRXSynapse/Pyrx.swift
//       Android: pyrx-synapse-android/synapse-core/src/main/kotlin/tech/pyrx/synapse/Pyrx.kt
//   - Cross-language wire reference (TypeScript):
//       pyrx-synapse-react-native/src/NativePyrxSynapse.ts
//       pyrx-synapse-react-native/src/events.ts

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/pyrx_synapse_messages.g.dart',
    dartPackageName: 'pyrx_synapse_platform_interface',
    swiftOut: '../pyrx_synapse_ios/ios/Classes/PyrxSynapseMessages.g.swift',
    swiftOptions: SwiftOptions(),
    kotlinOut:
        '../pyrx_synapse_android/android/src/main/kotlin/tech/pyrx/synapse/flutter/generated/PyrxSynapseMessages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'tech.pyrx.synapse.flutter.generated',
    ),
    copyrightHeader: 'pigeons/copyright_header.txt',
  ),
)

// =============================================================================
// SECTION 1: HostApi payload classes
//
// These are the Pigeon-managed wire types. The app-facing umbrella
// package wraps them in Dart-idiomatic classes (PR-2).
// =============================================================================

/// Arguments for [PyrxSynapseHostApi.initialize].
///
/// Mirrors `PyrxConfig` (iOS) and the equivalent Kotlin `PyrxConfig`
/// data class (Android). Flat fields keep the Pigeon codec simple;
/// optional fields cover the "use the SDK default" case.
class PyrxInitArgs {
  PyrxInitArgs({
    required this.workspaceId,
    required this.apiKey,
    required this.environment,
    this.baseUrl,
    this.logLevel,
  });

  /// Synapse workspace identifier (UUID v4 string).
  String workspaceId;

  /// Public ingestion API key. Format: `psk_{env}_{hex32}`.
  String apiKey;

  /// One of: `"production"`, `"sandbox"`, `"staging"`.
  String environment;

  /// Optional override for the ingestion base URL. Pass `null` to use
  /// the SDK default for the selected environment.
  String? baseUrl;

  /// One of: `"debug"`, `"info"`, `"warning"`, `"error"`, `"none"`.
  /// Defaults to `"info"` on the native side if `null`.
  String? logLevel;
}

/// Result of [PyrxSynapseHostApi.identify] and
/// [PyrxSynapseHostApi.alias].
///
/// Mirrors `IdentityResult` on both natives. Used to surface which
/// merge branch ran for support diagnostics.
class PyrxIdentityResult {
  PyrxIdentityResult({
    required this.contactId,
    required this.path,
    this.aliasedExternalId,
    required this.eventsReattributed,
    required this.devicesReattributed,
  });

  /// Server-assigned contact UUID.
  String contactId;

  /// One of: `"new"`, `"merge"`, `"alias"`, `"noop"`.
  String path;

  /// For `alias` results, the prior `externalId` that was merged in.
  /// Null for `identify` calls.
  String? aliasedExternalId;

  int eventsReattributed;
  int devicesReattributed;
}

/// Result of [PyrxSynapseHostApi.requestPushPermission].
///
/// Mirrors the OS-level permission verdict. Android maps Android 13+'s
/// runtime POST_NOTIFICATIONS result and "granted by default" on
/// older OS versions.
class PyrxPushPermissionResult {
  PyrxPushPermissionResult({required this.status});

  /// One of: `"granted"`, `"denied"`, `"provisional"`, `"notDetermined"`.
  String status;
}

/// Snapshot returned by [PyrxSynapseHostApi.debugInfo].
///
/// Mirrors `PyrxDebugInfo` on both natives. Used by customer support
/// and `/debug` screens.
class PyrxDebugInfo {
  PyrxDebugInfo({
    required this.sdkVersion,
    required this.platform,
    required this.initialized,
    this.workspaceId,
    this.environment,
    this.baseUrl,
    required this.logLevel,
    this.anonymousId,
    this.externalId,
    required this.trackingEnabled,
    required this.queueDepth,
    this.deviceTokenFingerprint,
  });

  String sdkVersion;
  String platform;
  bool initialized;
  String? workspaceId;
  String? environment;
  String? baseUrl;
  String logLevel;
  String? anonymousId;
  String? externalId;
  bool trackingEnabled;
  int queueDepth;
  String? deviceTokenFingerprint;
}

// =============================================================================
// SECTION 2: EventChannelApi payload classes
//
// One DTO per event variant. Mirrors the 5-event taxonomy fixed in
// Phase 9.2.1 (ADR-0005). Map<String, Object?> is used for the JSON
// portions; the app-facing Dart layer (PR-2) wraps these in the typed
// `PyrxAttributeValue` sealed class.
// =============================================================================

class PushReceivedEventDto {
  PushReceivedEventDto({
    required this.title,
    required this.body,
    this.pushLogId,
    required this.data,
    this.pyrxAttrs,
    required this.receivedAt,
  });

  String title;
  String body;
  String? pushLogId;
  Map<String?, Object?> data;
  Map<String?, Object?>? pyrxAttrs;

  /// ISO-8601 UTC timestamp from the native delegate.
  String receivedAt;
}

class PushClickedEventDto {
  PushClickedEventDto({
    this.pushLogId,
    this.deepLink,
    this.actionId,
    this.pyrxAttrs,
    required this.clickedAt,
  });

  String? pushLogId;
  String? deepLink;
  String? actionId;
  Map<String?, Object?>? pyrxAttrs;
  String clickedAt;
}

class IdentitySnapshotDto {
  IdentitySnapshotDto({
    this.anonymousId,
    this.externalId,
    required this.snapshotAt,
  });

  String? anonymousId;
  String? externalId;
  String snapshotAt;
}

class QueueDrainedEventDto {
  QueueDrainedEventDto({required this.count});

  int count;
}

class IdentityChangedEventDto {
  IdentityChangedEventDto({
    this.before,
    required this.after,
  });

  IdentitySnapshotDto? before;
  IdentitySnapshotDto after;
}

// =============================================================================
// SECTION 2b: In-app messaging DTOs (Phase 10 PR-2b)
//
// Mirror the iOS `Synapse.InApp.*` surface (PYRXSynapse 0.2.0) and the
// Android `Pyrx.inApp.*` surface (synapse-inapp 0.2.0). The shapes are
// cross-SDK symmetric per ADR-0009 D5 — browser / iOS / Android / RN /
// Flutter all carry the same semantic fields with the same names.
//
// The native SDKs own the wire (snake_case from the backend); these DTOs
// use the same idiomatic camelCase the rest of the Pigeon spec uses, so
// the bridge translates per-platform on the way in.
// =============================================================================

/// One call-to-action button on an [InAppMessageDto]. NLT source has
/// already been resolved against the current contact at fetch time —
/// `label` and `actionPayload` are ready to render verbatim.
///
/// `actionType` is one of: `"deep_link"`, `"dismiss"`, `"webview"`,
/// `"callback"` (lowercase snake_case, matching the wire). Pigeon's
/// codec stays string-based so the discriminator round-trips losslessly
/// across the bridge without per-language enum translation.
class InAppCtaDto {
  InAppCtaDto({
    required this.id,
    required this.label,
    required this.actionType,
    this.actionPayload,
  });

  String id;
  String label;
  String actionType;
  String? actionPayload;
}

/// One in-app message delivered to a registered render callback.
///
/// Mirrors the iOS `InAppMessage` struct + Android `InAppMessage` data
/// class field-for-field per ADR-0009 D5. The host app draws the UI —
/// the SDK does NOT render (ADR-0008 D2). `customData` is an arbitrary
/// JSON-shaped map the campaign emitter attaches; it crosses the
/// Pigeon codec as `Map<String?, Object?>` (the same shape `pyrx_attrs`
/// uses on push payloads) and is re-wrapped into a typed
/// `Map<String, PyrxAttributeValue>` by the umbrella package.
///
/// `expiresAt` is an ISO-8601 UTC string (matching the backend's
/// `datetime.isoformat()` default). The umbrella package parses it to
/// `DateTime?`.
class InAppMessageDto {
  InAppMessageDto({
    required this.id,
    required this.messageId,
    required this.placement,
    required this.title,
    required this.body,
    this.imageUrl,
    required this.ctas,
    this.customData,
    this.expiresAt,
    required this.priority,
  });

  /// Server-issued assignment id. Pass back via [markInteracted] /
  /// [dismiss] / observer events to identify the message.
  String id;

  /// The `in_app_messages.id` — stable across assignments.
  String messageId;

  /// Placement key the host app maps to a UI surface
  /// (e.g. `"home_banner"`).
  String placement;

  /// NLT-rendered title text.
  String title;

  /// NLT-rendered body text.
  String body;

  /// NLT-rendered image URL, or null.
  String? imageUrl;

  /// 0–2 CTAs (Phase 10 v1 scope).
  List<InAppCtaDto> ctas;

  /// Host-app-driven custom JSON. Same loosely-typed shape as the push
  /// `data` slot — values may themselves be deeply nested maps / lists.
  Map<String?, Object?>? customData;

  /// ISO-8601 UTC expiry instant. Null when the message has no expiry.
  String? expiresAt;

  /// Host-app sort / queue priority. Higher = more important.
  int priority;
}

class InAppMessageReceivedEventDto {
  InAppMessageReceivedEventDto({required this.message});

  InAppMessageDto message;
}

class InAppMessageDismissedEventDto {
  InAppMessageDismissedEventDto({
    required this.messageId,
    this.reason,
  });

  String messageId;
  String? reason;
}

/// Result of [PyrxSynapseHostApi.inAppShow]. Mirrors the iOS
/// `Synapse.ShowToken` and Android `ShowToken` — both opaque handles
/// that unregister the callback when closed.
///
/// Pigeon does not synthesise opaque-handle types across languages, so
/// we ship a small DTO carrying the (placement, subscriptionId) pair
/// the native side needs to look up the registration for
/// [PyrxSynapseHostApi.inAppUnregisterShow]. The Dart-side `ShowToken`
/// class wraps this DTO and exposes `dispose()` — the host app never
/// sees the subscription id.
class InAppShowTokenDto {
  InAppShowTokenDto({
    required this.placement,
    required this.subscriptionId,
  });

  String placement;
  int subscriptionId;
}

// =============================================================================
// SECTION 3: HostApi — Dart → native imperative surface
//
// 17 methods covering lifecycle, identity, events, push, privacy, and
// in-app messaging. Mirrors the public surface of `Pyrx.shared.*` /
// `Synapse.InApp.*` (iOS, PYRXSynapse 0.2.0) and `Pyrx.*` / `Pyrx.inApp.*`
// (Android, synapse-{core,push,inapp} 0.2.0).
// =============================================================================

@HostApi()
abstract class PyrxSynapseHostApi {
  // --- Lifecycle ----------------------------------------------------------
  @async
  void initialize(PyrxInitArgs args);

  @async
  void setLogLevel(String level);

  @async
  PyrxDebugInfo debugInfo();

  // --- Identity -----------------------------------------------------------
  /// [traitsJson] is a JSON-encoded `Map<String, Object?>` (or null). We
  /// pass JSON-as-string instead of a typed map because Pigeon's
  /// codec rejects deeply nested heterogeneous maps; serialising on
  /// the Dart side keeps the contract narrow and round-trip-stable.
  @async
  PyrxIdentityResult identify(String externalId, String? traitsJson);

  @async
  PyrxIdentityResult alias(String newExternalId);

  @async
  void logout();

  // --- Events -------------------------------------------------------------
  @async
  void track(String eventName, String? propertiesJson);

  @async
  void screen(String screenName, String? propertiesJson);

  // --- Push ---------------------------------------------------------------
  @async
  PyrxPushPermissionResult requestPushPermission(
    bool alert,
    bool sound,
    bool badge,
  );

  /// Trigger an explicit APNs/FCM token registration. On iOS this calls
  /// `UIApplication.shared.registerForRemoteNotifications()`; on Android
  /// this is a no-op (FCM auto-registers via the messaging service).
  @async
  void registerForPushNotifications();

  // --- Privacy ------------------------------------------------------------
  @async
  void setTrackingEnabled(bool enabled);

  @async
  void deleteUser();

  // --- In-app messaging (Phase 10 PR-2b) ---------------------------------
  //
  // Five methods mirror the iOS `Synapse.InApp.*` (PYRXSynapse 0.2.0)
  // and Android `Pyrx.inApp.*` (synapse-inapp 0.2.0) surfaces. The
  // lifecycle rules (identity-gating, polling coalesce, server-
  // authoritative cache, etc.) live native-side per ADR-0008; Flutter
  // is delegation.

  /// Register a render callback for [placement]. The native side
  /// dispatches fresh messages through the [onInAppMessageReceived]
  /// event stream; the Dart umbrella routes them to the per-token
  /// callback by matching [InAppShowTokenDto.subscriptionId] against
  /// `InAppMessage.id`/placement.
  ///
  /// Returns the [InAppShowTokenDto] handle the Dart umbrella wraps in
  /// a `ShowToken` that calls [inAppUnregisterShow] on dispose.
  @async
  InAppShowTokenDto inAppShow(String placement);

  /// Unregister a callback previously registered via [inAppShow]. Safe
  /// to call with an unknown id — native side no-ops.
  @async
  void inAppUnregisterShow(String placement, int subscriptionId);

  /// Sync-style read of currently-active messages from the in-memory
  /// cache. Does NOT trigger a poll. Pass `null` for [placement] to
  /// return every cached message (sorted by priority desc, then expiry
  /// asc to match the cross-SDK contract).
  @async
  List<InAppMessageDto> inAppGetActive(String? placement);

  /// Mark a message dismissed. Evicts from cache, fires the
  /// [onInAppMessageDismissed] event, and POSTs `/v1/in-app/log` with
  /// `event="dismissed"`. [reason] is host-side observer metadata only
  /// — it does NOT cross the wire (PR-1 backend has no `reason` field).
  @async
  void inAppDismiss(String messageId, String? reason);

  /// Mark a message interacted (a CTA was tapped). POSTs
  /// `/v1/in-app/log` with `event="interacted"` and `cta_id=ctaId`.
  /// Does NOT evict from cache.
  @async
  void inAppMarkInteracted(String messageId, String ctaId);

  /// Force an immediate poll. Coalesces with any in-flight poll
  /// (lifecycle rule 4). No-op when no placements are registered or
  /// the SDK is not yet identified.
  @async
  void inAppRefresh();
}

// =============================================================================
// SECTION 4: Event-stream wrapper + EventChannelApi
//
// Pigeon (27.x) requires all EventChannelApi methods to live on a single
// @EventChannelApi class. We model the 5-event taxonomy as a discriminated
// union wire type (`PyrxEventEnvelope`) emitted on one channel, then the
// app-facing umbrella (PR-2) unpacks the envelope into the sealed
// `PyrxEvent` Dart class.
//
// Note on Q3 of the Phase 9.3 plan: the plan flagged "one channel per
// event type vs. one channel emitting a discriminator" as an open
// sub-decision. Pigeon's runtime forces the second option, so we adopt
// it. The native bridges still subscribe ONCE to `Pyrx.events()` /
// `Pyrx.events` and convert each native event case into an envelope on
// the wire — no per-event channel multiplexing needed.
//
// Late-subscriber replay (the cold-start race) is handled NATIVE-SIDE
// — see Phase 9.2.1 PR-3 for the replay buffer of 4. Flutter
// subscribers attaching late still receive buffered events.
//
// Cold-start dedup (same push tap → exactly one of `PushClicked` OR
// `PushReceivedColdStart`, never both) is also native-side. Don't
// re-implement here.
// =============================================================================

/// Discriminator for [PyrxEventEnvelope]. Mirrors the case-set of the
/// native sealed types byte-for-byte.
///
/// Adding new cases is an additive change (per ADR-0005 D5). PR-2's
/// Dart consumer wraps a `default:` branch so unknown variants from
/// future native SDKs are tolerated; the umbrella's `Stream<PyrxEvent>`
/// drops unknown envelopes silently with a debug log.
///
/// Phase 10 PR-2b (ADR-0009 D5) extends the 5-event taxonomy to 7 by
/// adding [inAppMessageReceived] + [inAppMessageDismissed] — symmetric
/// with the browser/iOS/Android SDKs' equivalent events.
enum PyrxEventKind {
  pushReceived,
  pushClicked,
  pushReceivedColdStart,
  queueDrained,
  identityChanged,
  inAppMessageReceived,
  inAppMessageDismissed,
}

/// Single wire envelope for the 7-event observer surface. Exactly one of
/// the `*Payload` fields is non-null per envelope, matching [kind].
///
/// We use a flat-fields envelope instead of a Dart sealed class so
/// Pigeon's codec stays straightforward — Pigeon does not yet support
/// sealed-class generation across all three target languages.
class PyrxEventEnvelope {
  PyrxEventEnvelope({
    required this.kind,
    this.pushReceived,
    this.pushClicked,
    this.pushReceivedColdStart,
    this.queueDrained,
    this.identityChanged,
    this.inAppMessageReceived,
    this.inAppMessageDismissed,
  });

  PyrxEventKind kind;
  PushReceivedEventDto? pushReceived;
  PushClickedEventDto? pushClicked;
  PushReceivedEventDto? pushReceivedColdStart;
  QueueDrainedEventDto? queueDrained;
  IdentityChangedEventDto? identityChanged;
  InAppMessageReceivedEventDto? inAppMessageReceived;
  InAppMessageDismissedEventDto? inAppMessageDismissed;
}

@EventChannelApi()
abstract class PyrxSynapseEventApi {
  PyrxEventEnvelope streamEvents();
}
