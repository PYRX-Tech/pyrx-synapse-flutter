// Minimal example for pub.dev. Real Flutter UI lives in
// `examples/synapse_flutter_demo/` at the repo root.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pyrx_synapse/pyrx_synapse.dart';

Future<void> main() async {
  // 1. Initialize the SDK once at app start.
  await Synapse.initialize(
    const PyrxConfig(
      workspaceId: '<your-workspace-id>',
      apiKey: 'psk_test_<your-key>',
      environment: PyrxEnvironment.sandbox,
    ),
  );

  // 2. Subscribe to the merged Stream<PyrxEvent>. Exhaustive switch
  //    keeps the consumer honest if a new event type is added later
  //    (compiler flags the missing case at upgrade time).
  final subscription = Synapse.events.listen((event) {
    switch (event) {
      case PushReceived(:final event):
        debugPrint('foreground push: ${event.title}');
      case PushClicked(:final event):
        debugPrint('tap → deep link: ${event.deepLink}');
      case PushReceivedColdStart(:final event):
        debugPrint('cold start: ${event.title}');
      case QueueDrained(:final count):
        debugPrint('flushed $count events');
      case IdentityChanged(:final before, :final after):
        debugPrint(
          'identity ${before?.externalId ?? "(none)"} → '
          '${after.externalId ?? "(anon)"}',
        );
      case InAppMessageReceived(:final message):
        debugPrint('in-app: "${message.title}" @ ${message.placement}');
      case InAppMessageDismissed(:final messageId, :final reason):
        debugPrint('in-app dismissed: $messageId (${reason ?? "no reason"})');
    }
  });

  // 3. Bind a user identity + send an event.
  await Synapse.identify('user_123', traits: {'plan': 'pro'});
  await Synapse.track('home.viewed', properties: {'cohort': 'A'});

  // 4. Ask for OS push permission.
  final status = await Synapse.requestPushPermission();
  debugPrint('push permission: $status');

  // 5. Register a render callback for an in-app placement.
  //    Phase 10 PR-2b — the SDK delivers data; the host draws the UI.
  final token = await Synapse.inApp.show('home_banner', (message) {
    debugPrint('render banner: ${message.title} — ${message.body}');
  });

  // Tear down on app exit:
  await token.dispose();
  await subscription.cancel();
}
