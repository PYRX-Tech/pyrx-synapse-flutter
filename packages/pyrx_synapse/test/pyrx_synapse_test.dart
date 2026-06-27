// Smoke test for the umbrella package. PR-1 ships scaffolding only — the
// real `Synapse` namespace and `Stream<PyrxEvent>` merger land in PR-2.
//
// This test exists to:
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
    test('re-exports PyrxSynapsePlatform from the platform-interface package',
        () {
      // Just touching the symbol is enough — if the export chain is broken
      // this file will fail to compile.
      expect(PyrxSynapsePlatform.instance, isA<PyrxSynapsePlatform>());
    });

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
  });
}
