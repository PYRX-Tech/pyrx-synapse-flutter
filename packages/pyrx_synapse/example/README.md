# pyrx_synapse — minimal example

This is a minimal "API tour" snippet shipped in the package itself so
the pub.dev page renders a runnable code example.

For a **full Flutter app** demonstrating every public surface
(initialization, identity, events, push permission, push registration,
and the merged `Stream<PyrxEvent>` observer), see the in-repo sample
at
[`examples/synapse_flutter_demo/`](https://github.com/PYRX-Tech/pyrx-synapse-flutter/tree/main/examples/synapse_flutter_demo)
in the GitHub source tree. It includes:

- Workspace credential input + `Synapse.initialize`
- `identify`/`alias`/`logout` + an `IdentityChanged` observer
- `track`/`screen` with a `QueueDrained` counter
- `requestPushPermission`/`registerForPushNotifications` + filtered
  subscriptions for `PushReceived`/`PushClicked`/`PushReceivedColdStart`
- A full merged `Stream<PyrxEvent>` log

See the [umbrella README](../README.md) for an install + quickstart
walkthrough.
