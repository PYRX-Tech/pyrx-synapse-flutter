// PyrxSynapseHostApiImpl.swift
// pyrx_synapse_ios — iOS Pigeon HostApi implementation.
//
// Implements the Pigeon-generated `PyrxSynapseHostApi` protocol (from
// `Classes/PyrxSynapseMessages.g.swift`) by forwarding every method to
// the `Pyrx.shared` actor from PYRXSynapse 0.1.2+. Every call:
//
//   1. Decodes Pigeon-typed arguments into the native SDK's own types.
//   2. Hops into `Pyrx.shared`'s actor isolation with `Task { await … }`.
//   3. Resolves or rejects the Pigeon completion handler.
//
// Error mapping mirrors `pyrx-synapse-react-native/ios/.../PyrxSynapseImpl.swift`:
//
//   .notInitialized       → "not_initialized"
//   .invalidConfig        → "invalid_argument"
//   .network              → "network_error"
//   .keychainFailure      → "internal_error"
//   .alreadyInitialized   → "invalid_argument"
//   <anything else>       → "internal_error"
//
// The error code reaches the Dart-side caller as the `code` field of
// `FlutterError`; PR-2's `SynapseError` Dart class wraps these so app
// code can pattern-match without depending on Pigeon types directly.

import Flutter
import Foundation
import PYRXSynapse

final class PyrxSynapseHostApiImpl: PyrxSynapseHostApi {

  // MARK: Lifecycle

  func initialize(
    args: PyrxInitArgs,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let workspaceUuid = UUID(uuidString: args.workspaceId) else {
      completion(.failure(Self.flutterError(
        code: "invalid_argument",
        message: "workspaceId must be a UUID v4 string"
      )))
      return
    }

    let environment: PyrxEnvironment
    switch args.environment.lowercased() {
    case "production", "live":
      environment = .production
    case "sandbox", "staging", "test":
      environment = .sandbox
    default:
      completion(.failure(Self.flutterError(
        code: "invalid_argument",
        message: "environment must be one of: production, sandbox"
      )))
      return
    }

    let baseUrl: URL = {
      if let str = args.baseUrl, let url = URL(string: str) {
        return url
      }
      return PyrxConfig.defaultBaseUrl
    }()

    let logLevel = Self.parseLogLevel(args.logLevel) ?? .info

    let config = PyrxConfig(
      workspaceId: workspaceUuid,
      apiKey: args.apiKey,
      environment: environment,
      baseUrl: baseUrl,
      logLevel: logLevel,
      sdkVariant: "flutter"
    )

    Task {
      do {
        try await Pyrx.shared.initialize(config: config)
        completion(.success(()))
      } catch {
        completion(.failure(Self.translate(error)))
      }
    }
  }

  func setLogLevel(
    level: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let parsed = Self.parseLogLevel(level) else {
      completion(.failure(Self.flutterError(
        code: "invalid_argument",
        message: "level must be one of: debug, info, warning, error, none"
      )))
      return
    }
    Pyrx.shared.setLogLevel(parsed)
    completion(.success(()))
  }

  func debugInfo(
    completion: @escaping (Result<PyrxDebugInfo, Error>) -> Void
  ) {
    Task {
      let info = await Pyrx.shared.debugInfo()
      completion(.success(PyrxDebugInfo(
        sdkVersion: info.sdkVersion,
        platform: info.platform,
        initialized: info.initialized,
        workspaceId: info.workspaceId?.uuidString,
        environment: info.environment,
        baseUrl: info.baseUrl,
        logLevel: Self.logLevelString(info.logLevel),
        anonymousId: info.anonymousId,
        externalId: info.externalId,
        trackingEnabled: info.trackingEnabled,
        queueDepth: Int64(info.queueDepth),
        deviceTokenFingerprint: info.deviceTokenFingerprint
      )))
    }
  }

  // MARK: Identity

  func identify(
    externalId: String,
    traitsJson: String?,
    completion: @escaping (Result<PyrxIdentityResult, Error>) -> Void
  ) {
    let traits: [String: JSONValue]?
    do {
      traits = try Self.decodeTraits(traitsJson)
    } catch {
      completion(.failure(Self.flutterError(
        code: "invalid_argument",
        message: "traits is not valid JSON: \(error.localizedDescription)"
      )))
      return
    }

    Task {
      do {
        let result = try await Pyrx.shared.identify(externalId: externalId, traits: traits)
        completion(.success(Self.encodeIdentity(result)))
      } catch {
        completion(.failure(Self.translate(error)))
      }
    }
  }

  func alias(
    newExternalId: String,
    completion: @escaping (Result<PyrxIdentityResult, Error>) -> Void
  ) {
    Task {
      do {
        let result = try await Pyrx.shared.alias(newExternalId: newExternalId)
        completion(.success(Self.encodeIdentity(result)))
      } catch {
        completion(.failure(Self.translate(error)))
      }
    }
  }

  func logout(completion: @escaping (Result<Void, Error>) -> Void) {
    Task {
      do {
        try await Pyrx.shared.logout()
        completion(.success(()))
      } catch {
        completion(.failure(Self.translate(error)))
      }
    }
  }

  // MARK: Events

  func track(
    eventName: String,
    propertiesJson: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let properties: [String: JSONValue]?
    do {
      properties = try Self.decodeTraits(propertiesJson)
    } catch {
      completion(.failure(Self.flutterError(
        code: "invalid_argument",
        message: "properties is not valid JSON: \(error.localizedDescription)"
      )))
      return
    }

    Task {
      do {
        try await Pyrx.shared.track(eventName: eventName, properties: properties)
        completion(.success(()))
      } catch {
        completion(.failure(Self.translate(error)))
      }
    }
  }

  func screen(
    screenName: String,
    propertiesJson: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let properties: [String: JSONValue]?
    do {
      properties = try Self.decodeTraits(propertiesJson)
    } catch {
      completion(.failure(Self.flutterError(
        code: "invalid_argument",
        message: "properties is not valid JSON: \(error.localizedDescription)"
      )))
      return
    }

    Task {
      do {
        try await Pyrx.shared.screen(screenName: screenName, properties: properties)
        completion(.success(()))
      } catch {
        completion(.failure(Self.translate(error)))
      }
    }
  }

  // MARK: Push

  func requestPushPermission(
    alert: Bool,
    sound: Bool,
    badge: Bool,
    completion: @escaping (Result<PyrxPushPermissionResult, Error>) -> Void
  ) {
    var options: UNAuthorizationOptions = []
    if alert { options.insert(.alert) }
    if sound { options.insert(.sound) }
    if badge { options.insert(.badge) }

    Task {
      let status = await Pyrx.shared.requestPushPermission(options: options)
      completion(.success(PyrxPushPermissionResult(status: Self.permissionString(status))))
    }
  }

  func registerForPushNotifications(
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
      completion(.success(()))
    }
  }

  // MARK: Privacy

  func setTrackingEnabled(
    enabled: Bool,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    Task {
      await Pyrx.shared.setTrackingEnabled(enabled)
      completion(.success(()))
    }
  }

  func deleteUser(completion: @escaping (Result<Void, Error>) -> Void) {
    Task {
      do {
        try await Pyrx.shared.deleteUser()
        completion(.success(()))
      } catch {
        completion(.failure(Self.translate(error)))
      }
    }
  }

  // MARK: - Helpers

  /// Translate optional level-string into the SDK enum. Returns nil for
  /// unrecognised values so the caller can raise `invalid_argument`.
  private static func parseLogLevel(_ level: String?) -> LogLevel? {
    switch level?.lowercased() {
    case nil, "info":
      return .info
    case "debug":
      return .debug
    case "warning", "warn":
      return .warning
    case "error":
      return .error
    case "none", "off", "silent":
      return LogLevel.none
    default:
      return nil
    }
  }

  private static func logLevelString(_ level: LogLevel) -> String {
    switch level {
    case .debug: return "debug"
    case .info: return "info"
    case .warning: return "warning"
    case .error: return "error"
    case LogLevel.none: return "none"
    }
  }

  private static func permissionString(_ status: PushPermissionStatus) -> String {
    switch status {
    case .authorized: return "granted"
    case .denied: return "denied"
    case .provisional: return "provisional"
    case .ephemeral: return "ephemeral"
    case .notDetermined: return "notDetermined"
    }
  }

  /// Decode the JSON string Dart sends into the SDK's typed JSONValue map.
  /// Returns nil if the input is nil.
  private static func decodeTraits(_ json: String?) throws -> [String: JSONValue]? {
    guard let json = json, !json.isEmpty else { return nil }
    let data = Data(json.utf8)
    return try JSONDecoder().decode([String: JSONValue].self, from: data)
  }

  private static func encodeIdentity(_ result: IdentityResult) -> PyrxIdentityResult {
    PyrxIdentityResult(
      contactId: result.contactId.uuidString,
      path: result.path.rawValue,
      aliasedExternalId: result.aliasedExternalId,
      eventsReattributed: Int64(result.eventsReattributed),
      devicesReattributed: Int64(result.devicesReattributed)
    )
  }

  /// Map PyrxError cases to the wire-level error code set the Dart layer
  /// expects. Mirrors the RN bridge's translation table.
  private static func translate(_ error: Error) -> FlutterError {
    if let pyrxError = error as? PyrxError {
      switch pyrxError {
      case .notInitialized:
        return flutterError(code: "not_initialized", message: "Pyrx.shared.initialize has not completed")
      case .invalidConfig(let reason):
        return flutterError(code: "invalid_argument", message: reason)
      case .network(let info):
        return flutterError(code: "network_error", message: String(describing: info))
      case .keychainFailure(let status, let operation):
        return flutterError(code: "internal_error", message: "keychain failure on \(operation): OSStatus \(status)")
      case .alreadyInitialized:
        return flutterError(code: "invalid_argument", message: "Pyrx.shared.initialize was called twice with different configs")
      @unknown default:
        return flutterError(code: "internal_error", message: String(describing: pyrxError))
      }
    }
    return flutterError(code: "internal_error", message: error.localizedDescription)
  }

  private static func flutterError(code: String, message: String?) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}
