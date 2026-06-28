// EventsScreen — Synapse.track / Synapse.screen demo + QueueDrained
// counter via the merged event stream.
//
// Demonstrates:
//
//   - Synapse.track(eventName, properties: {...}) for arbitrary events
//   - Synapse.screen(screenName, properties: {...}) for navigation
//     tracking; in a real app you'd wire this into your router's
//     onGenerateRoute / NavigatorObserver hooks
//   - Watching the native queue flush via a Synapse.events filter on
//     QueueDrained — proves the events you sent actually left the device

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pyrx_synapse/pyrx_synapse.dart';

import '../state/init_state.dart';
import '../widgets/info_tile.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  int _trackInvocations = 0;
  int _screenInvocations = 0;
  int _queueDrainCount = 0;
  int _lastDrainCount = 0;
  String? _lastError;

  StreamSubscription<QueueDrained>? _drainSub;

  @override
  void initState() {
    super.initState();
    _drainSub = Synapse.events
        .where((e) => e is QueueDrained)
        .cast<QueueDrained>()
        .listen((evt) {
      if (!mounted) return;
      setState(() {
        _queueDrainCount += 1;
        _lastDrainCount = evt.count;
      });
    });
  }

  @override
  void dispose() {
    _drainSub?.cancel();
    super.dispose();
  }

  Future<void> _trackButtonPress() async {
    setState(() => _lastError = null);
    try {
      await Synapse.track(
        'demo.button.pressed',
        properties: {
          'screen': 'events',
          'invocation': _trackInvocations + 1,
          'random': DateTime.now().millisecondsSinceEpoch,
        },
      );
      if (!mounted) return;
      setState(() => _trackInvocations += 1);
    } catch (err) {
      if (!mounted) return;
      setState(() => _lastError = err.toString());
    }
  }

  Future<void> _trackScreen() async {
    setState(() => _lastError = null);
    try {
      await Synapse.screen(
        'events_screen',
        properties: {
          'invocation': _screenInvocations + 1,
        },
      );
      if (!mounted) return;
      setState(() => _screenInvocations += 1);
    } catch (err) {
      if (!mounted) return;
      setState(() => _lastError = err.toString());
    }
  }

  Future<void> _setTrackingEnabled(bool enabled) async {
    setState(() => _lastError = null);
    try {
      await Synapse.setTrackingEnabled(enabled);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tracking enabled = $enabled')),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _lastError = err.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: InitState.instance,
      builder: (context, _) {
        final enabled = InitState.instance.initialized;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Events', style: Theme.of(context).textTheme.headlineSmall),
              if (!enabled) ...[
                const SizedBox(height: 8),
                const Text('Initialize the SDK on the Init tab first.',
                    style: TextStyle(color: Colors.grey)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: enabled ? _trackButtonPress : null,
                icon: const Icon(Icons.touch_app),
                label: const Text('Synapse.track("demo.button.pressed")'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: enabled ? _trackScreen : null,
                icon: const Icon(Icons.layers),
                label: const Text('Synapse.screen("events_screen")'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          enabled ? () => _setTrackingEnabled(false) : null,
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause tracking'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          enabled ? () => _setTrackingEnabled(true) : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume tracking'),
                    ),
                  ),
                ],
              ),
              if (_lastError != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_lastError!),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      InfoTile(
                        label: 'track() calls',
                        value: _trackInvocations.toString(),
                      ),
                      InfoTile(
                        label: 'screen() calls',
                        value: _screenInvocations.toString(),
                      ),
                      InfoTile(
                        label: 'QueueDrained events',
                        value: _queueDrainCount.toString(),
                      ),
                      InfoTile(
                        label: 'Last drain count',
                        value: _lastDrainCount.toString(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'QueueDrained fires every time the native event queue '
                'flushes a non-empty batch. Watch this counter tick up '
                '~30s after you spam the track button (the SDK debounces).',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }
}
