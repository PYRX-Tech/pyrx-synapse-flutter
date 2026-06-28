// PushScreen — Synapse.requestPushPermission /
// registerForPushNotifications demo + push-event counters.
//
// Demonstrates:
//
//   - Requesting OS push permission (alert/sound/badge toggles)
//   - Explicitly triggering registration (iOS only — Android is a no-op
//     because FCM auto-registers via the messaging service)
//   - Counting PushReceived / PushClicked / PushReceivedColdStart via
//     three filtered subscriptions on Synapse.events
//   - Surfacing the most recent push payload so you can sanity-check
//     pyrx_attrs / deep links coming back from the dashboard

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pyrx_synapse/pyrx_synapse.dart';

import '../state/init_state.dart';
import '../widgets/info_tile.dart';

class PushScreen extends StatefulWidget {
  const PushScreen({super.key});

  @override
  State<PushScreen> createState() => _PushScreenState();
}

class _PushScreenState extends State<PushScreen> {
  PushPermissionStatus? _permissionStatus;
  bool _requesting = false;
  String? _lastError;
  bool _alert = true;
  bool _sound = true;
  bool _badge = true;

  PushReceivedEvent? _lastForegroundPush;
  PushClickedEvent? _lastClick;
  PushReceivedEvent? _lastColdStart;

  StreamSubscription<PushReceived>? _foregroundSub;
  StreamSubscription<PushClicked>? _clickSub;
  StreamSubscription<PushReceivedColdStart>? _coldStartSub;

  @override
  void initState() {
    super.initState();
    _foregroundSub = Synapse.events
        .where((e) => e is PushReceived)
        .cast<PushReceived>()
        .listen((evt) {
      if (!mounted) return;
      setState(() => _lastForegroundPush = evt.event);
    });
    _clickSub = Synapse.events
        .where((e) => e is PushClicked)
        .cast<PushClicked>()
        .listen((evt) {
      if (!mounted) return;
      setState(() => _lastClick = evt.event);
    });
    _coldStartSub = Synapse.events
        .where((e) => e is PushReceivedColdStart)
        .cast<PushReceivedColdStart>()
        .listen((evt) {
      if (!mounted) return;
      setState(() => _lastColdStart = evt.event);
    });
  }

  @override
  void dispose() {
    _foregroundSub?.cancel();
    _clickSub?.cancel();
    _coldStartSub?.cancel();
    super.dispose();
  }

  Future<void> _requestPermission() async {
    setState(() {
      _requesting = true;
      _lastError = null;
    });
    try {
      final status = await Synapse.requestPushPermission(
        alert: _alert,
        sound: _sound,
        badge: _badge,
      );
      if (!mounted) return;
      setState(() => _permissionStatus = status);
    } catch (err) {
      if (!mounted) return;
      setState(() => _lastError = err.toString());
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _registerForPush() async {
    setState(() => _lastError = null);
    try {
      await Synapse.registerForPushNotifications();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('registerForPushNotifications() returned')),
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
              Row(
                children: [
                  Text('Push',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(width: 12),
                  if (_permissionStatus != null)
                    StatusPill(
                      label: _permissionStatus!.name.toUpperCase(),
                      color: switch (_permissionStatus!) {
                        PushPermissionStatus.granted => Colors.green,
                        PushPermissionStatus.provisional => Colors.teal,
                        PushPermissionStatus.denied => Colors.red,
                        PushPermissionStatus.notDetermined => Colors.grey,
                      },
                    ),
                ],
              ),
              if (!enabled) ...[
                const SizedBox(height: 8),
                const Text('Initialize the SDK on the Init tab first.',
                    style: TextStyle(color: Colors.grey)),
              ],
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('alert'),
                value: _alert,
                onChanged: (v) => setState(() => _alert = v),
              ),
              SwitchListTile(
                title: const Text('sound'),
                value: _sound,
                onChanged: (v) => setState(() => _sound = v),
              ),
              SwitchListTile(
                title: const Text('badge'),
                value: _badge,
                onChanged: (v) => setState(() => _badge = v),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: enabled && !_requesting ? _requestPermission : null,
                icon: const Icon(Icons.notifications_active),
                label: const Text('requestPushPermission()'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: enabled ? _registerForPush : null,
                icon: const Icon(Icons.app_registration),
                label: const Text('registerForPushNotifications()'),
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
              Text('Last foreground push (PushReceived)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _pushReceivedCard(_lastForegroundPush),
              const SizedBox(height: 16),
              Text('Last cold-start push (PushReceivedColdStart)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _pushReceivedCard(_lastColdStart),
              const SizedBox(height: 16),
              Text('Last click (PushClicked)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _pushClickCard(_lastClick),
            ],
          ),
        );
      },
    );
  }

  Card _pushReceivedCard(PushReceivedEvent? evt) {
    if (evt == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('(no push of this kind observed yet)'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            InfoTile(label: 'title', value: evt.title),
            InfoTile(label: 'body', value: evt.body),
            InfoTile(
              label: 'pushLogId',
              value: evt.pushLogId ?? '<null>',
            ),
            InfoTile(
              label: 'receivedAt',
              value: evt.receivedAt.toIso8601String(),
            ),
            InfoTile(label: 'data keys', value: evt.data.keys.join(', ')),
            InfoTile(
              label: 'pyrxAttrs keys',
              value: evt.pyrxAttrs.keys.join(', '),
            ),
          ],
        ),
      ),
    );
  }

  Card _pushClickCard(PushClickedEvent? evt) {
    if (evt == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('(no click observed yet)'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            InfoTile(
              label: 'pushLogId',
              value: evt.pushLogId ?? '<null>',
            ),
            InfoTile(
              label: 'deepLink',
              value: evt.deepLink ?? '<null>',
            ),
            InfoTile(
              label: 'actionId',
              value: evt.actionId ?? '<body tap>',
            ),
            InfoTile(
              label: 'clickedAt',
              value: evt.clickedAt.toIso8601String(),
            ),
          ],
        ),
      ),
    );
  }
}
