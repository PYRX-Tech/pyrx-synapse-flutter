// Minimal example for pub.dev. Real Flutter UI lives in
// `examples/synapse_flutter_demo/` at the repo root.

import 'dart:async';

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
        print('foreground push: ${event.title}');
      case PushClicked(:final event):
        print('tap → deep link: ${event.deepLink}');
      case PushReceivedColdStart(:final event):
        print('cold start: ${event.title}');
      case QueueDrained(:final count):
        print('flushed $count events');
      case IdentityChanged(:final before, :final after):
        print(
          'identity ${before?.externalId ?? "(none)"} → '
          '${after.externalId ?? "(anon)"}',
        );
    }
  });

  // 3. Bind a user identity + send an event.
  await Synapse.identify('user_123', traits: {'plan': 'pro'});
  await Synapse.track('home.viewed', properties: {'cohort': 'A'});

  // 4. Ask for OS push permission.
  final status = await Synapse.requestPushPermission();
  print('push permission: $status');

  // Tear down on app exit:
  await subscription.cancel();
}
