// Federation re-export smoke tests for the umbrella package.
//
// The umbrella's job is to be the ONE import every customer needs.
// These tests are the guardrail that prevents the export barrel from
// silently dropping a public type during a refactor. If any of these
// assertions fails to compile, the umbrella is broken for downstream
// consumers.
//
// Detailed PR-2 surface tests (Synapse namespace, payloads, sealed
// events, PyrxAttributeValue, fromEnvelope) live in dedicated
// per-module test files alongside the implementation.

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrx_synapse/pyrx_synapse.dart';

void main() {
  group('pyrx_synapse umbrella re-exports (platform-interface barrel)', () {
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

  group('pyrx_synapse umbrella re-exports (PR-2 typed surface)', () {
    test('Synapse namespace is reachable via the umbrella import', () {
      // Touching the static type is enough — if the export chain is
      // broken this file fails to compile.
      expect(Synapse.events, isA<Stream<PyrxEvent>>());
    });

    test('PyrxConfig + PyrxEnvironment + PyrxLogLevel are reachable', () {
      const config = PyrxConfig(
        workspaceId: 'ws',
        apiKey: 'psk',
        environment: PyrxEnvironment.sandbox,
        logLevel: PyrxLogLevel.debug,
      );
      expect(config.environment, PyrxEnvironment.sandbox);
      expect(config.logLevel, PyrxLogLevel.debug);
    });

    test('PushPermissionStatus enum is reachable', () {
      expect(PushPermissionStatus.values, hasLength(4));
    });

    test('PyrxEvent sealed hierarchy is reachable (all 5 leaves)', () {
      // Re-exports of every sealed leaf so consumers can `switch` on
      // them with a single import.
      expect(const QueueDrained(0), isA<PyrxEvent>());
      // PushReceived / PushClicked / PushReceivedColdStart /
      // IdentityChanged each carry a non-default-constructible
      // payload — symbol reachability is the assertion that matters.
      expect(PushReceived, isA<Type>());
      expect(PushClicked, isA<Type>());
      expect(PushReceivedColdStart, isA<Type>());
      expect(IdentityChanged, isA<Type>());
    });

    test('PyrxAttributeValue sealed hierarchy is reachable', () {
      const v = PyrxAttributeStr('x');
      expect(v, isA<PyrxAttributeValue>());
      expect(PyrxAttributeValue.fromJson(null), isA<PyrxAttributeValue>());
    });

    test('payload data classes are reachable', () {
      final snap = IdentitySnapshot(
        anonymousId: 'a',
        externalId: 'b',
        snapshotAt: DateTime.utc(2026, 6, 28, 10),
      );
      expect(snap.anonymousId, 'a');

      final pushEvent = PushReceivedEvent(
        title: 't',
        body: 'b',
        pushLogId: null,
        data: const {},
        pyrxAttrs: const {},
        receivedAt: DateTime.utc(2026, 6, 28, 10),
      );
      expect(pushEvent.title, 't');

      final clickEvent = PushClickedEvent(
        pushLogId: null,
        deepLink: null,
        actionId: null,
        pyrxAttrs: const {},
        clickedAt: DateTime.utc(2026, 6, 28, 10),
      );
      expect(clickEvent.actionId, isNull);
    });
  });
}
