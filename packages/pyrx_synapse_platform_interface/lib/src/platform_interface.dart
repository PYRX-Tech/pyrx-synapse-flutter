// The abstract base class platform implementations of the PYRX Synapse
// Flutter SDK extend.
//
// Per Flutter's
// [federated plugin pattern](https://docs.flutter.dev/packages-and-plugins/developing-packages#federated-plugins),
// this contract sits between the app-facing `pyrx_synapse` package and
// the per-platform implementations (`pyrx_synapse_ios`,
// `pyrx_synapse_android`). A future `pyrx_synapse_web` (wrapping the
// browser SDK via JS interop) or `pyrx_synapse_macos` (when a macOS
// native SDK exists) can extend this class without modifying the
// umbrella or sibling platform packages.
//
// Each platform package's `registerWith()` static method installs a
// concrete subclass as [instance]; the umbrella reads from [instance]
// to route imperative calls and to subscribe to the event stream.

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'generated/pyrx_synapse_messages.g.dart';
import 'method_channel.dart';

/// Abstract platform interface for PYRX Synapse.
///
/// Subclass and call `PyrxSynapsePlatform.instance = MyImpl();` from your
/// platform package's `registerWith()` to override the default.
abstract class PyrxSynapsePlatform extends PlatformInterface {
  /// Constructs a `PyrxSynapsePlatform`. Subclasses MUST call this
  /// constructor (via `super()`) to ensure they pass the token verification
  /// `plugin_platform_interface` enforces.
  PyrxSynapsePlatform() : super(token: _token);

  static final Object _token = Object();

  static PyrxSynapsePlatform _instance = MethodChannelPyrxSynapse();

  /// The default instance of [PyrxSynapsePlatform] to use.
  ///
  /// Defaults to [MethodChannelPyrxSynapse], which routes through Pigeon-
  /// generated platform channels. Platform packages override this in
  /// their `registerWith()` entry points.
  static PyrxSynapsePlatform get instance => _instance;

  /// Setter for the platform-specific implementation. Verifies the
  /// platform-interface contract token; throws if the subclass did not
  /// `super()` through [PyrxSynapsePlatform] correctly.
  static set instance(PyrxSynapsePlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  // --------------------------------------------------------------------
  // Lifecycle
  // --------------------------------------------------------------------

  /// Initialise the SDK against a Synapse workspace.
  ///
  /// Throws platform-specific errors from the underlying native SDK
  /// (e.g. `not_initialized` from a second-call race, `invalid_argument`
  /// for bad config, `network_error` for backend unreachability).
  Future<void> initialize(PyrxInitArgs args) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Update the SDK's runtime log verbosity.
  ///
  /// Accepts one of: `"debug"`, `"info"`, `"warning"`, `"error"`, `"none"`.
  Future<void> setLogLevel(String level) {
    throw UnimplementedError('setLogLevel() has not been implemented.');
  }

  /// Snapshot of the SDK's internal state. Used by customer-support /
  /// debug surfaces.
  Future<PyrxDebugInfo> debugInfo() {
    throw UnimplementedError('debugInfo() has not been implemented.');
  }

  // --------------------------------------------------------------------
  // Identity
  // --------------------------------------------------------------------

  /// Identify a known user with the given [externalId]. [traitsJson] is
  /// a JSON-encoded `Map<String, Object?>` (or `null`) carrying optional
  /// contact properties.
  Future<PyrxIdentityResult> identify(String externalId, String? traitsJson) {
    throw UnimplementedError('identify() has not been implemented.');
  }

  Future<PyrxIdentityResult> alias(String newExternalId) {
    throw UnimplementedError('alias() has not been implemented.');
  }

  Future<void> logout() {
    throw UnimplementedError('logout() has not been implemented.');
  }

  // --------------------------------------------------------------------
  // Events
  // --------------------------------------------------------------------

  Future<void> track(String eventName, String? propertiesJson) {
    throw UnimplementedError('track() has not been implemented.');
  }

  Future<void> screen(String screenName, String? propertiesJson) {
    throw UnimplementedError('screen() has not been implemented.');
  }

  // --------------------------------------------------------------------
  // Push
  // --------------------------------------------------------------------

  Future<PyrxPushPermissionResult> requestPushPermission({
    bool alert = true,
    bool sound = true,
    bool badge = true,
  }) {
    throw UnimplementedError(
        'requestPushPermission() has not been implemented.');
  }

  Future<void> registerForPushNotifications() {
    throw UnimplementedError(
        'registerForPushNotifications() has not been implemented.');
  }

  // --------------------------------------------------------------------
  // Privacy
  // --------------------------------------------------------------------

  Future<void> setTrackingEnabled(bool enabled) {
    throw UnimplementedError('setTrackingEnabled() has not been implemented.');
  }

  Future<void> deleteUser() {
    throw UnimplementedError('deleteUser() has not been implemented.');
  }

  // --------------------------------------------------------------------
  // Events stream
  // --------------------------------------------------------------------

  /// Broadcast stream of [PyrxEventEnvelope] envelopes from the native
  /// SDK's observer surface.
  ///
  /// The umbrella `pyrx_synapse` package (PR-2) unpacks each envelope
  /// into the app-facing sealed `PyrxEvent` Dart type. Subscribers
  /// attaching late still receive recent events thanks to the native
  /// SDK's replay buffer of 4 (iOS PYRXSynapse 0.1.2 / Android
  /// synapse-core 0.1.4).
  Stream<PyrxEventEnvelope> events() {
    throw UnimplementedError('events() has not been implemented.');
  }
}
