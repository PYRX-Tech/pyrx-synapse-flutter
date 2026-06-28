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
// SECTION 3: HostApi — Dart → native imperative surface
//
// 12 methods covering lifecycle, identity, events, push, privacy. Mirrors
// the public surface of `Pyrx.shared.*` (iOS) and `Pyrx.*` (Android) as
// of PYRXSynapse 0.1.2 / synapse-core 0.1.4.
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
enum PyrxEventKind {
  pushReceived,
  pushClicked,
  pushReceivedColdStart,
  queueDrained,
  identityChanged,
}

/// Single wire envelope for the 5-event observer surface. Exactly one of
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
  });

  PyrxEventKind kind;
  PushReceivedEventDto? pushReceived;
  PushClickedEventDto? pushClicked;
  PushReceivedEventDto? pushReceivedColdStart;
  QueueDrainedEventDto? queueDrained;
  IdentityChangedEventDto? identityChanged;
}

@EventChannelApi()
abstract class PyrxSynapseEventApi {
  PyrxEventEnvelope streamEvents();
}
