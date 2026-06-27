// Smoke test for the umbrella package. PR-1 ships scaffolding only — the
// real `Synapse` namespace and `Stream<PyrxEvent>` merger land in PR-2.
//
// PR-1 scope:
//   - Prove the umbrella package compiles under `flutter test`.
//   - Prove the re-export of `pyrx_synapse_platform_interface` resolves
//     end-to-end (so customers writing `import 'package:pyrx_synapse/...'`
//     in PR-2 don't hit a transitive-dep gap).
//   - Anchor the test runner so `melos run test` has something to run in
//     this package on PR-1.

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrx_synapse/pyrx_synapse.dart';

void main() {
  group('pyrx_synapse umbrella package (PR-1 scaffold)', () {
    test(
      're-exports PyrxSynapsePlatform from the platform-interface package',
      () {
        // Just touching the symbol is enough — if the export chain is
        // broken this file will fail to compile.
        expect(PyrxSynapsePlatform.instance, isA<PyrxSynapsePlatform>());
      },
    );

    test('re-exports event DTO types from the platform-interface package', () {
      final dto = PushReceivedEventDto(
        title: 'hello',
        body: 'world',
        data: <String?, Object?>{},
        receivedAt: '2026-06-27T00:00:00Z',
      );
      expect(dto.title, 'hello');
      expect(dto.body, 'world');
    });

    test('re-exports the PyrxEventKind enum (all 5 cases visible)', () {
      // The umbrella must surface the closed taxonomy so PR-2's
      // sealed PyrxEvent class can switch over the wire kind.
      expect(PyrxEventKind.values, hasLength(5));
      expect(
        PyrxEventKind.values,
        containsAll([
          PyrxEventKind.pushReceived,
          PyrxEventKind.pushClicked,
          PyrxEventKind.pushReceivedColdStart,
          PyrxEventKind.queueDrained,
          PyrxEventKind.identityChanged,
        ]),
      );
    });

    test('re-exports MethodChannelPyrxSynapse', () {
      // PR-2's umbrella may instantiate this directly for testing; the
      // re-export keeps the dep surface single-package for customers.
      expect(MethodChannelPyrxSynapse(), isA<PyrxSynapsePlatform>());
    });

    test('re-exports PyrxIdentityResult DTO', () {
      final r = PyrxIdentityResult(
        contactId: 'c-1',
        path: 'first_sighting',
        eventsReattributed: 0,
        devicesReattributed: 0,
      );
      expect(r.contactId, 'c-1');
      expect(r.path, 'first_sighting');
      expect(r.aliasedExternalId, isNull);
    });

    test('re-exports PyrxDebugInfo DTO', () {
      final info = PyrxDebugInfo(
        sdkVersion: '0.1.0',
        platform: 'ios',
        initialized: true,
        logLevel: 'info',
        trackingEnabled: true,
        queueDepth: 0,
      );
      expect(info.sdkVersion, '0.1.0');
      expect(info.initialized, isTrue);
    });

    test('re-exports PyrxPushPermissionResult DTO', () {
      final r = PyrxPushPermissionResult(status: 'granted');
      expect(r.status, 'granted');
    });
  });
}
