/// iOS implementation of the PYRX Synapse Flutter SDK.
///
/// Customers do not import this library directly. Flutter's federated
/// plugin resolver wires it up automatically on iOS builds via the
/// `flutter:plugin:platforms:ios:dartPluginClass` entry in
/// `pubspec.yaml`. The [PyrxSynapseIos.registerWith] static method is
/// invoked by Flutter at plugin attach time and is responsible for
/// installing this class as the current `PyrxSynapsePlatform.instance`.
library pyrx_synapse_ios;

import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

/// iOS implementation of `PyrxSynapsePlatform`.
///
/// Inherits the default `MethodChannelPyrxSynapse` behaviour from the
/// platform-interface package — that base class routes calls through the
/// Pigeon-generated `PyrxSynapseHostApi` proxy, whose handlers are
/// installed in Swift by `ios/Classes/PyrxSynapsePlugin.swift`. So this
/// subclass exists purely as the federation marker: it overrides nothing
/// today, but having it as a distinct type means future iOS-only
/// behaviour (e.g. APNs-specific helpers in PR-2+) can land here without
/// disturbing the platform-interface package or the Android impl.
class PyrxSynapseIos extends MethodChannelPyrxSynapse {
  /// Called by Flutter's plugin machinery on iOS at engine-attach time.
  static void registerWith() {
    PyrxSynapsePlatform.instance = PyrxSynapseIos();
  }
}
