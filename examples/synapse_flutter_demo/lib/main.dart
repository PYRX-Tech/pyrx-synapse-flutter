// Sample app entry point.
//
// Most of the interesting bits live in `src/`. This file is intentionally
// minimal so the SDK call sites are easy to find:
//
//   - `src/app.dart`              — MaterialApp + bottom-nav scaffold
//   - `src/screens/init_screen.dart`   — Synapse.initialize + config inputs
//   - `src/screens/identity_screen.dart` — identify / alias / logout
//   - `src/screens/events_screen.dart`   — track / screen
//   - `src/screens/push_screen.dart`     — requestPushPermission /
//     registerForPushNotifications
//   - `src/screens/observer_screen.dart` — full Synapse.events stream view
//
// The app does NOT auto-call Synapse.initialize. You enter your workspace
// credentials on the Init screen and tap "Initialize" — that mirrors the
// shape of a real onboarding flow and keeps the sample buildable without
// real credentials in your `.env`.

import 'package:flutter/material.dart';

import 'src/app.dart';

void main() {
  runApp(const SynapseDemoApp());
}
