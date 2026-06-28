// InitScreen — Synapse.initialize + debugInfo viewer.
//
// Demonstrates:
//
//   - PyrxConfig construction with all five inputs (workspaceId,
//     apiKey, environment, baseUrl optional, logLevel optional)
//   - Synapse.initialize() future-await + error surfacing
//   - Synapse.debugInfo() round-trip after init succeeds
//
// You enter your workspace credentials here. They're not persisted
// across app launches — that's intentional for the sample (no plaintext
// secret on disk). In a real app, store them at build time via
// --dart-define or a similar mechanism.

import 'package:flutter/material.dart';
import 'package:pyrx_synapse/pyrx_synapse.dart';

import '../state/init_state.dart';
import '../widgets/info_tile.dart';

class InitScreen extends StatefulWidget {
  const InitScreen({super.key});

  @override
  State<InitScreen> createState() => _InitScreenState();
}

class _InitScreenState extends State<InitScreen> {
  final _workspaceIdCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  PyrxEnvironment _env = PyrxEnvironment.sandbox;
  PyrxLogLevel _logLevel = PyrxLogLevel.info;

  bool _initInFlight = false;
  DebugInfo? _debugInfo;

  @override
  void dispose() {
    _workspaceIdCtrl.dispose();
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final workspaceId = _workspaceIdCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    if (workspaceId.isEmpty || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workspace ID and API key are required.'),
        ),
      );
      return;
    }
    final config = PyrxConfig(
      workspaceId: workspaceId,
      apiKey: apiKey,
      environment: _env,
      baseUrl:
          _baseUrlCtrl.text.trim().isEmpty ? null : _baseUrlCtrl.text.trim(),
      logLevel: _logLevel,
    );
    setState(() => _initInFlight = true);
    InitState.instance.markInitializing();
    try {
      await Synapse.initialize(config);
      InitState.instance.markInitialized(config);
      await _refreshDebug();
    } catch (err) {
      InitState.instance.markFailed(err);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Initialize failed: $err')),
      );
    } finally {
      if (mounted) setState(() => _initInFlight = false);
    }
  }

  Future<void> _refreshDebug() async {
    try {
      final info = await Synapse.debugInfo();
      if (mounted) setState(() => _debugInfo = info);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('debugInfo failed: $err')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: InitState.instance,
      builder: (context, _) {
        final initialized = InitState.instance.initialized;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Initialise',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(width: 12),
                  if (initialized)
                    const StatusPill(label: 'INITIALIZED', color: Colors.green)
                  else if (_initInFlight)
                    const StatusPill(
                        label: 'INITIALIZING', color: Colors.orange)
                  else
                    const StatusPill(label: 'NOT READY', color: Colors.grey),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your workspace credentials, then tap Initialize. '
                'The SDK will boot in-process and start emitting events on '
                'the observer screen.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _workspaceIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Workspace ID',
                  hintText: 'UUID v4',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyCtrl,
                decoration: const InputDecoration(
                  labelText: 'API key',
                  hintText: 'psk_test_... or psk_live_...',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Base URL (optional)',
                  hintText: 'Defaults to synapse-events.pyrx.tech',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<PyrxEnvironment>(
                      initialValue: _env,
                      decoration: const InputDecoration(
                        labelText: 'Environment',
                        border: OutlineInputBorder(),
                      ),
                      items: PyrxEnvironment.values
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e.name),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _env = v ?? PyrxEnvironment.sandbox),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<PyrxLogLevel>(
                      initialValue: _logLevel,
                      decoration: const InputDecoration(
                        labelText: 'Log level',
                        border: OutlineInputBorder(),
                      ),
                      items: PyrxLogLevel.values
                          .map((l) => DropdownMenuItem(
                                value: l,
                                child: Text(l.name),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _logLevel = v ?? PyrxLogLevel.info),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _initInFlight ? null : _initialize,
                icon: const Icon(Icons.bolt),
                label: const Text('Initialize'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: initialized ? _refreshDebug : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh debugInfo()'),
              ),
              if (InitState.instance.lastError != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Last error: ${InitState.instance.lastError}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
              if (_debugInfo != null) ...[
                const SizedBox(height: 24),
                Text('Synapse.debugInfo()',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        InfoTile(
                            label: 'sdkVersion', value: _debugInfo!.sdkVersion),
                        InfoTile(
                            label: 'platform', value: _debugInfo!.platform),
                        InfoTile(
                          label: 'initialized',
                          value: _debugInfo!.initialized.toString(),
                        ),
                        InfoTile(
                          label: 'workspaceId',
                          value: _debugInfo!.workspaceId ?? '<null>',
                        ),
                        InfoTile(
                          label: 'environment',
                          value: _debugInfo!.environment ?? '<null>',
                        ),
                        InfoTile(
                          label: 'baseUrl',
                          value: _debugInfo!.baseUrl ?? '<default>',
                        ),
                        InfoTile(
                            label: 'logLevel', value: _debugInfo!.logLevel),
                        InfoTile(
                          label: 'anonymousId',
                          value: _debugInfo!.anonymousId ?? '<not set>',
                        ),
                        InfoTile(
                          label: 'externalId',
                          value: _debugInfo!.externalId ?? '<not set>',
                        ),
                        InfoTile(
                          label: 'trackingEnabled',
                          value: _debugInfo!.trackingEnabled.toString(),
                        ),
                        InfoTile(
                          label: 'queueDepth',
                          value: _debugInfo!.queueDepth.toString(),
                        ),
                        InfoTile(
                          label: 'deviceToken',
                          value: _truncateToken(
                              _debugInfo!.deviceTokenFingerprint),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _truncateToken(String? token) {
    if (token == null) return '<not registered>';
    if (token.length <= 24) return token;
    return '${token.substring(0, 12)}…${token.substring(token.length - 8)}';
  }
}
