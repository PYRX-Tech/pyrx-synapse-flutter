// Default [PyrxSynapsePlatform] implementation backed by the Pigeon-
// generated `PyrxSynapseHostApi` proxy and `PyrxSynapseEventApi` stream.
//
// Both `pyrx_synapse_ios` and `pyrx_synapse_android` extend this class
// without overriding the imperative methods — the native side
// implements the Pigeon-generated HostApi protocol, so the Dart side
// just calls through. Platform packages exist as federation markers
// (`PyrxSynapseIos`, `PyrxSynapseAndroid`) so PR-2+ can add platform-
// specific helpers (e.g. APNs token introspection on iOS) without
// touching this file or the Android impl.

import 'generated/pyrx_synapse_messages.g.dart';
import 'platform_interface.dart';

class MethodChannelPyrxSynapse extends PyrxSynapsePlatform {
  /// Visible-for-testing — replace via the Pigeon-generated constructor
  /// in tests that fake the HostApi proxy.
  final PyrxSynapseHostApi _hostApi;

  /// Visible-for-testing — replace the Pigeon-generated event API helper
  /// in tests. PR-2's umbrella consumes this stream and exposes a
  /// merged `Stream<PyrxEvent>`.
  final Stream<PyrxEventEnvelope> _eventsStream;

  MethodChannelPyrxSynapse({
    PyrxSynapseHostApi? hostApi,
    Stream<PyrxEventEnvelope>? eventsStream,
  })  : _hostApi = hostApi ?? PyrxSynapseHostApi(),
        _eventsStream = eventsStream ?? streamEvents();

  // ----- Lifecycle ---------------------------------------------------

  @override
  Future<void> initialize(PyrxInitArgs args) => _hostApi.initialize(args);

  @override
  Future<void> setLogLevel(String level) => _hostApi.setLogLevel(level);

  @override
  Future<PyrxDebugInfo> debugInfo() => _hostApi.debugInfo();

  // ----- Identity ----------------------------------------------------

  @override
  Future<PyrxIdentityResult> identify(String externalId, String? traitsJson) =>
      _hostApi.identify(externalId, traitsJson);

  @override
  Future<PyrxIdentityResult> alias(String newExternalId) =>
      _hostApi.alias(newExternalId);

  @override
  Future<void> logout() => _hostApi.logout();

  // ----- Events ------------------------------------------------------

  @override
  Future<void> track(String eventName, String? propertiesJson) =>
      _hostApi.track(eventName, propertiesJson);

  @override
  Future<void> screen(String screenName, String? propertiesJson) =>
      _hostApi.screen(screenName, propertiesJson);

  // ----- Push --------------------------------------------------------

  @override
  Future<PyrxPushPermissionResult> requestPushPermission({
    bool alert = true,
    bool sound = true,
    bool badge = true,
  }) =>
      _hostApi.requestPushPermission(alert, sound, badge);

  @override
  Future<void> registerForPushNotifications() =>
      _hostApi.registerForPushNotifications();

  // ----- Privacy -----------------------------------------------------

  @override
  Future<void> setTrackingEnabled(bool enabled) =>
      _hostApi.setTrackingEnabled(enabled);

  @override
  Future<void> deleteUser() => _hostApi.deleteUser();

  // ----- In-app messaging (Phase 10 PR-2b) ---------------------------

  @override
  Future<InAppShowTokenDto> inAppShow(String placement) =>
      _hostApi.inAppShow(placement);

  @override
  Future<void> inAppUnregisterShow(String placement, int subscriptionId) =>
      _hostApi.inAppUnregisterShow(placement, subscriptionId);

  @override
  Future<List<InAppMessageDto>> inAppGetActive(String? placement) =>
      _hostApi.inAppGetActive(placement);

  @override
  Future<void> inAppDismiss(String messageId, String? reason) =>
      _hostApi.inAppDismiss(messageId, reason);

  @override
  Future<void> inAppMarkInteracted(String messageId, String ctaId) =>
      _hostApi.inAppMarkInteracted(messageId, ctaId);

  @override
  Future<void> inAppRefresh() => _hostApi.inAppRefresh();

  // ----- Events stream ----------------------------------------------

  @override
  Stream<PyrxEventEnvelope> events() => _eventsStream;
}
