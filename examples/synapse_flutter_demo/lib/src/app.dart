// SynapseDemoApp — root MaterialApp + a 5-tab bottom-nav scaffold.
//
// Each tab corresponds to one slice of the SDK surface. The scaffold
// keeps every screen mounted (via IndexedStack) so subscriptions on
// `Synapse.events` aren't torn down when the user switches tabs.

import 'package:flutter/material.dart';

import 'screens/events_screen.dart';
import 'screens/identity_screen.dart';
import 'screens/init_screen.dart';
import 'screens/observer_screen.dart';
import 'screens/push_screen.dart';
import 'state/event_log.dart';

class SynapseDemoApp extends StatefulWidget {
  const SynapseDemoApp({super.key});

  @override
  State<SynapseDemoApp> createState() => _SynapseDemoAppState();
}

class _SynapseDemoAppState extends State<SynapseDemoApp> {
  late final EventLog _eventLog;

  @override
  void initState() {
    super.initState();
    // Singleton-ish: one EventLog per app instance. It subscribes to
    // Synapse.events the first time it's read, so cold-start replay is
    // captured.
    _eventLog = EventLog();
  }

  @override
  void dispose() {
    _eventLog.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PYRX Synapse Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D9E75)),
      ),
      home: _DemoHomeShell(eventLog: _eventLog),
    );
  }
}

class _DemoHomeShell extends StatefulWidget {
  const _DemoHomeShell({required this.eventLog});

  final EventLog eventLog;

  @override
  State<_DemoHomeShell> createState() => _DemoHomeShellState();
}

class _DemoHomeShellState extends State<_DemoHomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      const InitScreen(),
      const IdentityScreen(),
      const EventsScreen(),
      const PushScreen(),
      ObserverScreen(eventLog: widget.eventLog),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('PYRX Synapse Demo'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bolt), label: 'Init'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Identity'),
          NavigationDestination(icon: Icon(Icons.event_note), label: 'Events'),
          NavigationDestination(icon: Icon(Icons.notifications), label: 'Push'),
          NavigationDestination(icon: Icon(Icons.stream), label: 'Observer'),
        ],
      ),
    );
  }
}
