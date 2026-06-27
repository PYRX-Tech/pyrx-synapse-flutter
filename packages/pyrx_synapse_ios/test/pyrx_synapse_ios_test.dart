// Dart-side smoke test for pyrx_synapse_ios.
//
// PR-1 scope: prove the federation marker class registers cleanly as
// the PyrxSynapsePlatform.instance and that the inherited
// MethodChannelPyrxSynapse default impl is the underlying behaviour.
//
// The actual iOS Swift bridge (PyrxSynapsePlugin.swift,
// PyrxSynapseHostApiImpl.swift, PyrxEventStreamHandler.swift) is
// exercised in PR-1's XCTest harness (TODO: lands in PR-3 alongside the
// sample app build, once we have a Flutter iOS host project to drive
// the Pod install). This Dart test runs in a pure-Dart VM via
// `flutter test`, so it must stay platform-channel-free.

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrx_synapse_ios/pyrx_synapse_ios.dart';
import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

void main() {
  group('PyrxSynapseIos', () {
    test('registerWith installs itself as PyrxSynapsePlatform.instance', () {
      PyrxSynapseIos.registerWith();
      expect(PyrxSynapsePlatform.instance, isA<PyrxSynapseIos>());
    });

    test('inherits MethodChannelPyrxSynapse behaviour', () {
      // PyrxSynapseIos extends MethodChannelPyrxSynapse — the
      // federation marker does not override imperative methods. PR-2+
      // may add iOS-specific helpers but the inheritance contract is
      // load-bearing today.
      PyrxSynapseIos.registerWith();
      final inst = PyrxSynapsePlatform.instance;
      expect(inst, isA<MethodChannelPyrxSynapse>());
    });
  });
}
