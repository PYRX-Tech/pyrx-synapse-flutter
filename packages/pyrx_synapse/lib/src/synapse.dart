// Synapse — the imperative Dart API surface customers consume.
//
//   import 'package:pyrx_synapse/pyrx_synapse.dart';
//
//   await Synapse.initialize(const PyrxConfig(
//     workspaceId: '...',
//     apiKey: 'psk_test_...',
//     environment: PyrxEnvironment.sandbox,
//   ));
//   await Synapse.identify('user_123', traits: {'plan': 'pro'});
//
// This module is a thin transform-and-delegate layer over the
// platform-interface package:
//
//   1. **Friendlier types at the API boundary.** [PyrxConfig] uses
//      `PyrxEnvironment` and `PyrxLogLevel` enums; the bridge spec
//      (Pigeon) uses plain strings. We narrow / encode at this seam.
//   2. **JSON envelope for traits / properties.** Arbitrary maps cross
//      the bridge as JSON strings — the Pigeon contract documented
//      that "deeply nested heterogeneous maps" don't survive the
//      standard codec. The encode happens here so the asymmetry is
//      confined to one file.
//   3. **Fail-fast input validation.** Empty strings, non-finite
//      numbers, and other malformed inputs throw [ArgumentError]
//      BEFORE crossing the bridge, saving a native round-trip.
//   4. **The merged Stream<PyrxEvent>.** The platform-interface
//      exposes a Pigeon-shaped `Stream<PyrxEventEnvelope>`; this
//      file unpacks each envelope into the sealed [PyrxEvent] leaf
//      so consumers never see the wire shape.
//
// No state is held in this module. The platform interface and native
// SDK own everything; this file is stateless transforms.

import 'dart:async';
import 'dart:convert';

import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

import 'pyrx_event.dart';

// --------------------------------------------------------------------
// Public types
// --------------------------------------------------------------------

/// Environment discriminator for [PyrxConfig]. Maps to the native
/// SDKs' `live` / `test` divider.
enum PyrxEnvironment {
  /// Live production workspace. Real customers, real billing.
  production,

  /// Sandbox workspace. Test traffic. Real backend, isolated data.
  sandbox,

  /// Internal-only staging. Most apps should not pick this.
  staging;

  /// Wire value the native SDKs expect.
  String get wireValue {
    switch (this) {
      case PyrxEnvironment.production:
        return 'production';
      case PyrxEnvironment.sandbox:
        return 'sandbox';
      case PyrxEnvironment.staging:
        return 'staging';
    }
  }
}

/// Runtime log verbosity. Maps to the native SDKs' `LogLevel` enum.
enum PyrxLogLevel {
  debug,
  info,
  warning,
  error,
  none;

  String get wireValue {
    switch (this) {
      case PyrxLogLevel.debug:
        return 'debug';
      case PyrxLogLevel.info:
        return 'info';
      case PyrxLogLevel.warning:
        return 'warning';
      case PyrxLogLevel.error:
        return 'error';
      case PyrxLogLevel.none:
        return 'none';
    }
  }
}

/// Push permission verdict returned by [Synapse.requestPushPermission].
/// `provisional` is iOS-only (always treated as `granted` on Android).
enum PushPermissionStatus {
  granted,
  denied,
  provisional,
  notDetermined;

  static PushPermissionStatus fromWire(String value) {
    switch (value) {
      case 'granted':
        return PushPermissionStatus.granted;
      case 'denied':
        return PushPermissionStatus.denied;
      case 'provisional':
        return PushPermissionStatus.provisional;
      case 'notDetermined':
        return PushPermissionStatus.notDetermined;
      default:
        // Loud-fail on native-bridge wire drift.
        throw StateError(
          'Unknown PushPermissionStatus wire value: "$value"',
        );
    }
  }
}

/// Customer-facing config for [Synapse.initialize].
class PyrxConfig {
  const PyrxConfig({
    required this.workspaceId,
    required this.apiKey,
    required this.environment,
    this.baseUrl,
    this.logLevel,
  });

  /// Synapse workspace identifier (UUID v4 string).
  final String workspaceId;

  /// Public ingestion API key. Format: `psk_{env}_{hex32}`.
  final String apiKey;

  /// Which Synapse environment to talk to.
  final PyrxEnvironment environment;

  /// Optional override for the ingestion base URL. `null` uses the
  /// SDK default for [environment].
  final String? baseUrl;

  /// Optional override for the initial log verbosity. `null` uses
  /// the SDK default (`info`).
  final PyrxLogLevel? logLevel;
}

/// Merge / first-sighting verdict returned by [Synapse.identify] and
/// [Synapse.alias]. Useful for support diagnostics when a customer
/// asks "did identify just create a new contact?".
class IdentityResult {
  const IdentityResult({
    required this.contactId,
    required this.path,
    required this.aliasedExternalId,
    required this.eventsReattributed,
    required this.devicesReattributed,
  });

  /// Server-assigned contact UUID.
  final String contactId;

  /// One of: `"new"`, `"merge"`, `"alias"`, `"noop"`.
  final String path;

  /// For `alias` results, the prior `externalId` that was merged in.
  /// `null` for `identify` calls.
  final String? aliasedExternalId;

  /// Number of events re-attributed to this contact during the merge.
  final int eventsReattributed;

  /// Number of devices re-attributed to this contact during the merge.
  final int devicesReattributed;

  factory IdentityResult._fromDto(PyrxIdentityResult dto) => IdentityResult(
        contactId: dto.contactId,
        path: dto.path,
        aliasedExternalId: dto.aliasedExternalId,
        eventsReattributed: dto.eventsReattributed,
        devicesReattributed: dto.devicesReattributed,
      );
}

/// Diagnostic snapshot of the SDK's internal state. Useful for debug
/// menus and customer-support bundles.
class DebugInfo {
  const DebugInfo({
    required this.sdkVersion,
    required this.platform,
    required this.initialized,
    required this.workspaceId,
    required this.environment,
    required this.baseUrl,
    required this.logLevel,
    required this.anonymousId,
    required this.externalId,
    required this.trackingEnabled,
    required this.queueDepth,
    required this.deviceTokenFingerprint,
  });

  final String sdkVersion;
  final String platform;
  final bool initialized;
  final String? workspaceId;
  final String? environment;
  final String? baseUrl;
  final String logLevel;
  final String? anonymousId;
  final String? externalId;
  final bool trackingEnabled;
  final int queueDepth;
  final String? deviceTokenFingerprint;

  factory DebugInfo._fromDto(PyrxDebugInfo dto) => DebugInfo(
        sdkVersion: dto.sdkVersion,
        platform: dto.platform,
        initialized: dto.initialized,
        workspaceId: dto.workspaceId,
        environment: dto.environment,
        baseUrl: dto.baseUrl,
        logLevel: dto.logLevel,
        anonymousId: dto.anonymousId,
        externalId: dto.externalId,
        trackingEnabled: dto.trackingEnabled,
        queueDepth: dto.queueDepth,
        deviceTokenFingerprint: dto.deviceTokenFingerprint,
      );
}

// --------------------------------------------------------------------
// Validation helpers
// --------------------------------------------------------------------

void _requireNonEmpty(String name, String value) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, name, 'must be a non-empty string');
  }
}

/// JSON-encode a properties bag, or return `null` for `null` input.
/// Throws [ArgumentError] if the map can't be encoded (e.g. contains
/// a non-JSON-representable value).
String? _encodeOptionalProperties(
  Map<String, Object?>? props,
  String name,
) {
  if (props == null) {
    return null;
  }
  try {
    return jsonEncode(props);
  } on JsonUnsupportedObjectError catch (err) {
    throw ArgumentError.value(
      props,
      name,
      'failed to serialise as JSON: ${err.cause ?? err.unsupportedObject}',
    );
  }
}

// --------------------------------------------------------------------
// The Synapse namespace
// --------------------------------------------------------------------

/// Imperative SDK surface. Mirrors the 12 methods on the native iOS +
/// Android SDKs 1:1 (per Pigeon `PyrxSynapseHostApi`).
///
/// Lifecycle:
///
///   1. [Synapse.initialize] — once, at app start, before any other call
///   2. [Synapse.events] — subscribe early to catch cold-start events
///   3. [Synapse.identify] when the user signs in; [Synapse.logout]
///      when they sign out
///   4. [Synapse.track] / [Synapse.screen] for events
///   5. [Synapse.requestPushPermission] when ready to ask
///
/// All methods are static; the class is not instantiable.
class Synapse {
  Synapse._();

  /// Override hook for tests. Production code reads [PyrxSynapsePlatform.instance]
  /// directly. Tests set this to a fake implementation to intercept
  /// every method call without touching the platform channel.
  static PyrxSynapsePlatform get _platform => PyrxSynapsePlatform.instance;

  // ------------------- Lifecycle -------------------

  /// Initialise the SDK against a Synapse workspace. MUST be called
  /// before any other method.
  ///
  /// Idempotent: calling twice with the same [config] is a no-op on
  /// the native side. Calling twice with a differing config rejects
  /// with a native-side `invalid_argument` error.
  static Future<void> initialize(PyrxConfig config) {
    _requireNonEmpty('config.workspaceId', config.workspaceId);
    _requireNonEmpty('config.apiKey', config.apiKey);
    if (config.baseUrl != null) {
      _requireNonEmpty('config.baseUrl', config.baseUrl!);
    }
    final args = PyrxInitArgs(
      workspaceId: config.workspaceId,
      apiKey: config.apiKey,
      environment: config.environment.wireValue,
      baseUrl: config.baseUrl,
      logLevel: config.logLevel?.wireValue,
    );
    return _platform.initialize(args);
  }

  /// Update runtime log verbosity.
  static Future<void> setLogLevel(PyrxLogLevel level) {
    return _platform.setLogLevel(level.wireValue);
  }

  /// Diagnostic snapshot — useful for debug menus + bug reports.
  static Future<DebugInfo> debugInfo() async {
    final dto = await _platform.debugInfo();
    return DebugInfo._fromDto(dto);
  }

  // ------------------- Identity -------------------

  /// Bind the current device to an external identity. The native SDKs
  /// handle the anonymous-to-known merge on the server side.
  ///
  /// [traits] is JSON-encoded and forwarded; values must be
  /// JSON-representable (`String`, `num`, `bool`, `null`, `List`, `Map`).
  static Future<IdentityResult> identify(
    String externalId, {
    Map<String, Object?>? traits,
  }) async {
    _requireNonEmpty('externalId', externalId);
    final traitsJson = _encodeOptionalProperties(traits, 'traits');
    final dto = await _platform.identify(externalId, traitsJson);
    return IdentityResult._fromDto(dto);
  }

  /// Rename the active external identity. Same return shape as
  /// [identify] so callers can branch on [IdentityResult.path].
  static Future<IdentityResult> alias(String newExternalId) async {
    _requireNonEmpty('newExternalId', newExternalId);
    final dto = await _platform.alias(newExternalId);
    return IdentityResult._fromDto(dto);
  }

  /// Drop the current identity and roll a fresh anonymousId.
  static Future<void> logout() => _platform.logout();

  // ------------------- Events -------------------

  /// Track a custom event. Returns once the event has been enqueued —
  /// NOT once it has been delivered to the backend (the native queue
  /// owns delivery + retry + drop semantics).
  static Future<void> track(
    String eventName, {
    Map<String, Object?>? properties,
  }) {
    _requireNonEmpty('eventName', eventName);
    final propertiesJson = _encodeOptionalProperties(properties, 'properties');
    return _platform.track(eventName, propertiesJson);
  }

  /// Track a screen view.
  static Future<void> screen(
    String screenName, {
    Map<String, Object?>? properties,
  }) {
    _requireNonEmpty('screenName', screenName);
    final propertiesJson = _encodeOptionalProperties(properties, 'properties');
    return _platform.screen(screenName, propertiesJson);
  }

  // ------------------- Push -------------------

  /// Ask the OS for permission to send push notifications and register
  /// for remote notifications. The token capture is automatic — see
  /// the iOS `PyrxSynapseAppDelegate` and Android `PyrxMessagingService`
  /// base classes that PR-1 ships.
  static Future<PushPermissionStatus> requestPushPermission({
    bool alert = true,
    bool sound = true,
    bool badge = true,
  }) async {
    final dto = await _platform.requestPushPermission(
      alert: alert,
      sound: sound,
      badge: badge,
    );
    return PushPermissionStatus.fromWire(dto.status);
  }

  /// Trigger an explicit APNs/FCM token registration. On iOS this calls
  /// `UIApplication.shared.registerForRemoteNotifications()`; on Android
  /// this is a no-op (FCM auto-registers via the messaging service).
  static Future<void> registerForPushNotifications() =>
      _platform.registerForPushNotifications();

  // ------------------- Privacy -------------------

  /// Toggle the SDK's tracking gate. `false` drains the queue and
  /// disables future event capture; identity is preserved.
  static Future<void> setTrackingEnabled(bool enabled) =>
      _platform.setTrackingEnabled(enabled);

  /// GDPR delete — drops local identity, wipes the encrypted store,
  /// drains the queue, and asks the backend to forget the contact.
  /// Irreversible.
  static Future<void> deleteUser() => _platform.deleteUser();

  // ------------------- Events stream -------------------

  /// The merged event stream — every event the SDK publishes (5 types
  /// per Phase 9.2.1 ADR-0005) flows through here.
  ///
  /// **Broadcast**: multiple concurrent listeners are supported; each
  /// gets every event. Cancel your subscription on widget dispose to
  /// stop receiving events.
  ///
  /// **Late-subscriber replay**: PYRXSynapse 0.1.2 / synapse-core 0.1.4
  /// buffer the most recent 4 events native-side. The first Dart
  /// subscriber receives those buffered events; subsequent subscribers
  /// that attach AFTER the first one will see only NEW events. To
  /// reliably catch cold-start events, subscribe early — e.g. right
  /// after [Synapse.initialize] resolves.
  ///
  /// **Wire-drift policy**: events with an unknown envelope kind (none
  /// expected without a native-SDK release) are silently dropped. A
  /// malformed envelope (kind says X but the X slot is null) throws
  /// `StateError` synchronously on the stream — that surfaces as a
  /// stream error to subscribers.
  static Stream<PyrxEvent> get events {
    return _platform
        .events()
        .map(PyrxEvent.fromEnvelope)
        .where((event) => event != null)
        .cast<PyrxEvent>();
  }
}
