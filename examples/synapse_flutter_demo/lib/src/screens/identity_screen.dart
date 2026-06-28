// IdentityScreen — Synapse.identify / alias / logout demo + live
// IdentityChanged event display.
//
// Demonstrates:
//
//   - Synapse.identify(externalId, traits: {...}) with a traits payload
//   - Synapse.alias(newExternalId) for the "user changed their handle"
//     case
//   - Synapse.logout() and the resulting anonymous→named transition
//   - Listening to IdentityChanged via a Synapse.events.where() filter,
//     which is the recommended pattern for typed sub-streams (see
//     docs/STREAMS.md "filtering by event type").

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pyrx_synapse/pyrx_synapse.dart';

import '../state/init_state.dart';
import '../widgets/info_tile.dart';

class IdentityScreen extends StatefulWidget {
  const IdentityScreen({super.key});

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  final _externalIdCtrl = TextEditingController(text: 'user_123');
  final _emailCtrl = TextEditingController(text: 'jane@example.com');
  final _aliasCtrl = TextEditingController(text: 'user_renamed');

  IdentityResult? _lastIdentityResult;
  IdentityChanged? _lastIdentityEvent;
  String? _lastError;

  StreamSubscription<IdentityChanged>? _identitySub;

  @override
  void initState() {
    super.initState();
    // Filtered stream — only IdentityChanged events. Documented in
    // docs/STREAMS.md as the canonical "subscribe to a single event
    // type" idiom.
    _identitySub = Synapse.events
        .where((e) => e is IdentityChanged)
        .cast<IdentityChanged>()
        .listen((evt) {
      if (!mounted) return;
      setState(() => _lastIdentityEvent = evt);
    });
  }

  @override
  void dispose() {
    _identitySub?.cancel();
    _externalIdCtrl.dispose();
    _emailCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _identify() async {
    setState(() => _lastError = null);
    try {
      final result = await Synapse.identify(
        _externalIdCtrl.text.trim(),
        traits: {
          if (_emailCtrl.text.trim().isNotEmpty)
            'email': _emailCtrl.text.trim(),
          'plan': 'pro',
          'demo_app': true,
        },
      );
      if (!mounted) return;
      setState(() => _lastIdentityResult = result);
    } catch (err) {
      if (!mounted) return;
      setState(() => _lastError = err.toString());
    }
  }

  Future<void> _alias() async {
    setState(() => _lastError = null);
    try {
      final result = await Synapse.alias(_aliasCtrl.text.trim());
      if (!mounted) return;
      setState(() => _lastIdentityResult = result);
    } catch (err) {
      if (!mounted) return;
      setState(() => _lastError = err.toString());
    }
  }

  Future<void> _logout() async {
    setState(() => _lastError = null);
    try {
      await Synapse.logout();
      if (!mounted) return;
      setState(() => _lastIdentityResult = null);
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
              Text('Identity',
                  style: Theme.of(context).textTheme.headlineSmall),
              if (!enabled) ...[
                const SizedBox(height: 8),
                const Text(
                  'Initialize the SDK on the Init tab first.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _externalIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'External ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email (trait, optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: enabled ? _identify : null,
                icon: const Icon(Icons.login),
                label: const Text('identify()'),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _aliasCtrl,
                decoration: const InputDecoration(
                  labelText: 'New external ID for alias()',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: enabled ? _alias : null,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('alias()'),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: enabled ? _logout : null,
                icon: const Icon(Icons.logout),
                label: const Text('logout()'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
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
              if (_lastIdentityResult != null) ...[
                const SizedBox(height: 24),
                Text('Last IdentityResult',
                    style: Theme.of(context).textTheme.titleMedium),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        InfoTile(
                            label: 'contactId',
                            value: _lastIdentityResult!.contactId),
                        InfoTile(
                            label: 'path', value: _lastIdentityResult!.path),
                        InfoTile(
                          label: 'aliasedExternalId',
                          value: _lastIdentityResult!.aliasedExternalId ??
                              '<null>',
                        ),
                        InfoTile(
                          label: 'eventsReattributed',
                          value: _lastIdentityResult!.eventsReattributed
                              .toString(),
                        ),
                        InfoTile(
                          label: 'devicesReattributed',
                          value: _lastIdentityResult!.devicesReattributed
                              .toString(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text('Last IdentityChanged event',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Synapse.events.where((e) => e is IdentityChanged).cast<IdentityChanged>().listen(...)',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _lastIdentityEvent == null
                      ? const Text('(no IdentityChanged event observed yet)')
                      : Column(
                          children: [
                            InfoTile(
                              label: 'before.externalId',
                              value: _lastIdentityEvent!.before?.externalId ??
                                  '<null>',
                            ),
                            InfoTile(
                              label: 'before.anonymousId',
                              value: _lastIdentityEvent!.before?.anonymousId ??
                                  '<null>',
                            ),
                            InfoTile(
                              label: 'after.externalId',
                              value: _lastIdentityEvent!.after.externalId ??
                                  '<null>',
                            ),
                            InfoTile(
                              label: 'after.anonymousId',
                              value: _lastIdentityEvent!.after.anonymousId ??
                                  '<null>',
                            ),
                            InfoTile(
                              label: 'transition',
                              value: _classifyTransition(_lastIdentityEvent!),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _classifyTransition(IdentityChanged evt) {
    final beforeExt = evt.before?.externalId;
    final afterExt = evt.after.externalId;
    if (beforeExt == null && afterExt != null) return 'LOGIN';
    if (beforeExt != null && afterExt == null) return 'LOGOUT';
    if (beforeExt != null && afterExt != null && beforeExt != afterExt) {
      return 'SWITCH';
    }
    return 'INIT-OR-NO-OP';
  }
}
