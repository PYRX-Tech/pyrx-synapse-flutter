// Dart-side smoke test for pyrx_synapse_android.
//
// PR-1 scope: prove the federation marker class registers cleanly as
// the PyrxSynapsePlatform.instance and that the inherited
// MethodChannelPyrxSynapse default impl is the underlying behaviour.
//
// The actual Android Kotlin bridge (PyrxSynapsePlugin.kt,
// PyrxSynapseHostApiImpl.kt, PyrxEventStreamHandler.kt) is exercised
// in PR-1's Robolectric / instrumentation tests (TODO: lands in PR-3
// alongside the sample app build, once we have a Flutter Android host
// project to drive the Gradle build). This Dart test runs in a pure-
// Dart VM via `flutter test`, so it must stay platform-channel-free.

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrx_synapse_android/pyrx_synapse_android.dart';
import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

void main() {
  group('PyrxSynapseAndroid', () {
    test('registerWith installs itself as PyrxSynapsePlatform.instance', () {
      PyrxSynapseAndroid.registerWith();
      expect(PyrxSynapsePlatform.instance, isA<PyrxSynapseAndroid>());
    });

    test('inherits MethodChannelPyrxSynapse behaviour', () {
      PyrxSynapseAndroid.registerWith();
      final inst = PyrxSynapsePlatform.instance;
      expect(inst, isA<MethodChannelPyrxSynapse>());
    });
  });
}
