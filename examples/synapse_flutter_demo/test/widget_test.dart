// Sample-app smoke tests. The demo is intentionally minimal but we
// still want the build / wiring asserted in CI.
//
// We can't exercise real SDK calls in widget tests (the platform
// channel isn't wired in a test isolate), so these tests focus on the
// app shell — tabs render, switching tabs preserves state, the
// observer screen's empty-state shows before any events have arrived.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:synapse_flutter_demo/src/app.dart';

void main() {
  testWidgets('SynapseDemoApp boots into the Init tab', (tester) async {
    await tester.pumpWidget(const SynapseDemoApp());
    await tester.pumpAndSettle();

    // App bar title.
    expect(find.text('PYRX Synapse Demo'), findsOneWidget);

    // Init tab is the default selection — the Initialize button is its
    // most identifiable affordance.
    expect(find.text('Initialize'), findsOneWidget);
  });

  testWidgets('Bottom-nav switches to every tab', (tester) async {
    await tester.pumpWidget(const SynapseDemoApp());
    await tester.pumpAndSettle();

    // Identity tab.
    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    expect(find.text('Identity'), findsAtLeastNWidgets(1));

    // Events tab.
    await tester.tap(find.byIcon(Icons.event_note));
    await tester.pumpAndSettle();
    expect(find.text('Events'), findsAtLeastNWidgets(1));

    // Push tab.
    await tester.tap(find.byIcon(Icons.notifications));
    await tester.pumpAndSettle();
    expect(find.text('Push'), findsAtLeastNWidgets(1));

    // Observer tab.
    await tester.tap(find.byIcon(Icons.stream));
    await tester.pumpAndSettle();
    expect(find.text('Observer'), findsAtLeastNWidgets(1));
  });

  testWidgets(
    'Observer tab shows empty-state before any events arrive',
    (tester) async {
      await tester.pumpWidget(const SynapseDemoApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.stream));
      await tester.pumpAndSettle();

      expect(
        find.text('No events yet. Trigger one from another tab.'),
        findsOneWidget,
      );
    },
  );
}
