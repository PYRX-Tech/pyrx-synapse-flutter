// ObserverScreen — the full Synapse.events log + per-type counters.
//
// Demonstrates:
//
//   - The full merged Stream<PyrxEvent> consumed via a shared
//     EventLog (subscribed once at app boot in src/app.dart, so the
//     native replay buffer flushes its cold-start events into our log
//     before any screen widget mounts).
//   - The recommended "single broadcast subscription, fan out via
//     ChangeNotifier" pattern: one StreamSubscription per app, many
//     widgets consume via ListenableBuilder. Avoids re-subscribing
//     every time a screen rebuilds — see docs/STREAMS.md "Avoiding
//     subscription leaks".
//
// This is also the screen QA exercises end-to-end: trigger an event
// from any other tab, watch it land here within ~50ms.

import 'package:flutter/material.dart';

import '../state/event_log.dart';
import '../widgets/info_tile.dart';

class ObserverScreen extends StatelessWidget {
  const ObserverScreen({super.key, required this.eventLog});

  final EventLog eventLog;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: eventLog,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Observer',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      InfoTile(
                        label: 'PushReceived',
                        value: eventLog.pushReceivedCount.toString(),
                      ),
                      InfoTile(
                        label: 'PushClicked',
                        value: eventLog.pushClickedCount.toString(),
                      ),
                      InfoTile(
                        label: 'PushReceivedColdStart',
                        value: eventLog.coldStartCount.toString(),
                      ),
                      InfoTile(
                        label: 'QueueDrained',
                        value: eventLog.queueDrainCount.toString(),
                      ),
                      InfoTile(
                        label: 'IdentityChanged',
                        value: eventLog.identityChangeCount.toString(),
                      ),
                      InfoTile(
                        label: 'Last identity',
                        value: eventLog.lastIdentitySnapshot?.externalId ??
                            (eventLog.lastIdentitySnapshot?.anonymousId ??
                                '<none>'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Stream entries (${eventLog.entries.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: eventLog.entries.isEmpty ? null : eventLog.clear,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: eventLog.entries.isEmpty
                    ? const Center(
                        child: Text(
                          'No events yet. Trigger one from another tab.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: eventLog.entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final entry = eventLog.entries[i];
                          return ListTile(
                            dense: true,
                            title: Text(
                              entry.summary,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
