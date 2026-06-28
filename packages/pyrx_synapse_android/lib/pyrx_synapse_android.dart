/// Android implementation of the PYRX Synapse Flutter SDK.
///
/// Customers do not import this library directly. Flutter's federated
/// plugin resolver wires it up automatically on Android builds via the
/// `flutter:plugin:platforms:android:dartPluginClass` entry in
/// `pubspec.yaml`. The [PyrxSynapseAndroid.registerWith] static method
/// is invoked by Flutter at plugin attach time and is responsible for
/// installing this class as the current `PyrxSynapsePlatform.instance`.
library pyrx_synapse_android;

import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

/// Android implementation of `PyrxSynapsePlatform`.
///
/// Inherits `MethodChannelPyrxSynapse` — the platform-interface default
/// that routes calls through the Pigeon-generated `PyrxSynapseHostApi`
/// proxy. The Kotlin side is the actual implementation
/// (`packages/pyrx_synapse_android/android/src/main/kotlin/.../PyrxSynapsePlugin.kt`).
///
/// This subclass exists as the federation marker — having a distinct
/// type means future Android-only Dart-side helpers (e.g. exposing
/// Android-specific debug fields in PR-2+) land here without disturbing
/// either the platform-interface contract or the iOS impl.
class PyrxSynapseAndroid extends MethodChannelPyrxSynapse {
  /// Called by Flutter's plugin machinery on Android at engine-attach time.
  static void registerWith() {
    PyrxSynapsePlatform.instance = PyrxSynapseAndroid();
  }
}
