// PyrxSynapsePlugin.swift
// pyrx_synapse_ios — iOS implementation of the PYRX Synapse Flutter SDK.
//
// This file is the FlutterPlugin entry point. Flutter calls
// `register(with:)` at app launch (Flutter's plugin machinery
// auto-generates a `GeneratedPluginRegistrant.m` that invokes us). We do
// three things at registration:
//
//   1. Construct a single `PyrxSynapseHostApi` implementor
//      (`PyrxSynapseHostApiImpl`) and register it via the Pigeon-
//      generated `PyrxSynapseHostApiSetup.setUp`. From this point on,
//      any Dart-side `Synapse.identify(...)` etc. routes through the
//      Pigeon codec to one of the methods on the impl.
//
//   2. Construct a single `StreamEventsStreamHandler` subclass
//      (`PyrxEventStreamHandler`) and register it via the Pigeon-
//      generated `StreamEventsStreamHandler.register`. The handler
//      subscribes to `Pyrx.shared.events()` (the AsyncStream observer
//      surface added in Phase 9.2.1 / PYRXSynapse 0.1.2) the first time
//      Dart attaches, holds the Task as a property, and cancels on
//      detach. One native subscription fans out to all Dart subscribers
//      because Flutter's event channel handles the multi-listener
//      bookkeeping.
//
//   3. Capture cold-start push payload if present (`launchOptions[.remoteNotification]`)
//      and forward it to `Pyrx.shared.recordColdStartLaunch(userInfo:)`.
//      The published SDK's replay buffer of 4 means a Dart subscriber
//      that attaches after the cold-start delivery (the common case
//      because the Flutter engine boots in 0.5-2s while the OS delivers
//      the launch payload synchronously at `application:didFinishLaunching`)
//      still receives the buffered event.
//
// What this file deliberately does NOT do
// ---------------------------------------
// - Swizzle UIApplicationDelegate. The Flutter plugin model gives us
//   first-class hooks (`application(_:didFinishLaunchingWithOptions:)`
//   on FlutterAppDelegate) without monkey-patching. The cost is that
//   the SDK only sees notifications routed through the Flutter
//   delegate; apps that override didReceiveRemoteNotification in their
//   own AppDelegate must call through to super.
// - Implement push permission requests itself. That's delegated to
//   `Pyrx.shared.requestPushPermission(...)` which already handles the
//   UNUserNotificationCenter dance.
// - Handle device-token registration in the plugin layer.
//   `Pyrx.shared.handleDeviceToken(_:)` is called from the customer's
//   AppDelegate `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
//   override. PR-2 / customer docs (PR-3) document the wiring; this
//   plugin doesn't try to swizzle around it.

import Flutter
import PYRXSynapse
import UIKit
import UserNotifications

public class PyrxSynapsePlugin: NSObject, FlutterPlugin {

  /// Held strongly for the lifetime of the plugin. The Pigeon setUp call
  /// keeps these alive through the Flutter binary messenger, but holding
  /// them explicitly here makes the lifecycle visible and prevents the
  /// "compiler warning: unused" the Pigeon-setup-without-retain pattern
  /// would otherwise produce.
  private let hostApiImpl: PyrxSynapseHostApiImpl
  private let eventStreamHandler: PyrxEventStreamHandler

  init(messenger: FlutterBinaryMessenger) {
    self.hostApiImpl = PyrxSynapseHostApiImpl()
    self.eventStreamHandler = PyrxEventStreamHandler()
    super.init()
    PyrxSynapseHostApiSetup.setUp(binaryMessenger: messenger, api: hostApiImpl)
    StreamEventsStreamHandler.register(
      with: messenger,
      streamHandler: eventStreamHandler
    )
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = PyrxSynapsePlugin(messenger: registrar.messenger())
    registrar.publish(plugin)
    registrar.addApplicationDelegate(plugin)
  }

  // ---- UIApplicationDelegate hooks ----
  //
  // These fire on the Flutter delegate (provided the customer's app
  // root inherits from `FlutterAppDelegate`, the default for new Flutter
  // projects). For customers using a custom UIApplicationDelegate, the
  // `addApplicationDelegate` call in `register` makes Flutter forward
  // the lifecycle calls to us anyway.

  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      Task {
        await Pyrx.shared.recordColdStartLaunch(userInfo: userInfo)
      }
    }
    return true
  }

  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Task {
      do {
        _ = try await Pyrx.shared.handleDeviceToken(deviceToken)
      } catch {
        // The Dart-side caller of `registerForPushNotifications`
        // already received a successful completion; failures here are
        // device-registration races we surface via the SDK's logger
        // (not propagated to Dart because no Dart caller is awaiting
        // this delegate callback).
        NSLog("[PYRXSynapse Flutter] handleDeviceToken failed: \(error)")
      }
    }
  }

  public func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    Pyrx.shared.handleRegistrationError(error)
  }
}
