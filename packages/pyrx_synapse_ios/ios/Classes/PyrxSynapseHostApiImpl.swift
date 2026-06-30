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

  // MARK: - In-app messaging (Phase 10 PR-2b)
  //
  // Five methods that delegate to `Synapse.InApp.*` — the public iOS
  // facade in PYRXSynapse 0.2.0. The per-placement render callback
  // we register with `Synapse.InApp.show` is a no-op: the per-message
  // dispatch into Dart happens via the `inAppMessageReceived` envelope
  // on the shared event stream (PyrxEventStreamHandler), so Flutter
  // consumers never see two dispatch paths for the same message. The
  // callback only exists to keep the placement alive on the native
  // manager (so it keeps polling).
  //
  // We hand Dart a monotonic Flutter-side subscription id and stash
  // the corresponding `Synapse.ShowToken` in a dictionary; the
  // companion `inAppUnregisterShow` looks the token up by id and
  // cancels it. This indirection exists because `Synapse.ShowToken`'s
  // `subscriptionId` is private — we can't surface it to Dart even
  // though the cross-SDK contract names a subscription handle.

  /// Monotonically-increasing Flutter-side subscription id. Allocated
  /// per `inAppShow` call; never reused. Atomic via the `tokensLock`.
  private var nextSubscriptionId: Int64 = 0
  private var tokensById: [Int64: Synapse.ShowToken] = [:]
  private let tokensLock = NSLock()

  func inAppShow(
    placement: String,
    completion: @escaping (Result<InAppShowTokenDto, Error>) -> Void
  ) {
    Task {
      let token = await Synapse.InApp.show(placement: placement) { _ in
        // No-op — the Dart umbrella dispatches per-placement via the
        // shared event stream's `inAppMessageReceived` envelope. The
        // callback is required by `Synapse.InApp.show` so the manager
        // tracks the placement; we don't need to do anything here.
      }

      let id = await MainActor.run { () -> Int64 in
        tokensLock.lock()
        defer { tokensLock.unlock() }
        nextSubscriptionId &+= 1
        let id = nextSubscriptionId
        tokensById[id] = token
        return id
      }

      completion(.success(InAppShowTokenDto(
        placement: placement,
        subscriptionId: id
      )))
    }
  }

  func inAppUnregisterShow(
    placement: String,
    subscriptionId: Int64,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let token: Synapse.ShowToken? = {
      tokensLock.lock()
      defer { tokensLock.unlock() }
      return tokensById.removeValue(forKey: subscriptionId)
    }()
    // `cancel()` is idempotent; calling on the deinit-already-fired
    // path is a silent no-op. Safe to call here even if Dart racing
    // with two `dispose()` from different code paths drops the
    // entry from the dictionary first.
    token?.cancel()
    completion(.success(()))
  }

  func inAppGetActive(
    placement: String?,
    completion: @escaping (Result<[InAppMessageDto], Error>) -> Void
  ) {
    Task {
      let messages = await Synapse.InApp.getActive(placement: placement)
      completion(.success(messages.map(Self.encodeInAppMessage)))
    }
  }

  func inAppDismiss(
    messageId: String,
    reason: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    Task {
      await Synapse.InApp.dismiss(messageId: messageId, reason: reason)
      completion(.success(()))
    }
  }

  func inAppMarkInteracted(
    messageId: String,
    ctaId: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    Task {
      await Synapse.InApp.markInteracted(messageId: messageId, ctaId: ctaId)
      completion(.success(()))
    }
  }

  func inAppRefresh(completion: @escaping (Result<Void, Error>) -> Void) {
    Task {
      await Synapse.InApp.refresh()
      completion(.success(()))
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

  // MARK: - In-app messaging encoders

  /// Convert a published `InAppMessage` into the Pigeon-wire DTO.
  /// CTAs lose nothing; `customData` JSONValues are projected onto the
  /// `Map<String?, Object?>` Pigeon shape (same flattening as
  /// `pyrx_attrs` on push payloads). `expiresAt` is rendered as ISO-8601
  /// UTC — the same format the backend emits.
  static func encodeInAppMessage(_ message: InAppMessage) -> InAppMessageDto {
    return InAppMessageDto(
      id: message.id,
      messageId: message.messageId,
      placement: message.placement,
      title: message.title,
      body: message.body,
      imageUrl: message.imageUrl,
      ctas: message.ctas.map(encodeInAppCta),
      customData: message.customData.map(encodeCustomDataMap),
      expiresAt: message.expiresAt.map(iso8601.string(from:)),
      priority: Int64(message.priority)
    )
  }

  private static func encodeInAppCta(_ cta: InAppCta) -> InAppCtaDto {
    return InAppCtaDto(
      id: cta.id,
      label: cta.label,
      actionType: cta.actionType.rawValue,
      actionPayload: cta.actionPayload
    )
  }

  /// Project a typed JSONValue map onto the loosely-typed Pigeon
  /// `Map<String?, Object?>` shape. NSNull stands in for nil so the
  /// Pigeon codec round-trips the explicit-null case faithfully.
  private static func encodeCustomDataMap(_ map: [String: JSONValue]) -> [String?: Any?] {
    var out: [String?: Any?] = [:]
    for (k, v) in map {
      out[k] = encodeJSONValue(v)
    }
    return out
  }

  private static func encodeJSONValue(_ value: JSONValue) -> Any {
    switch value {
    case .null:
      return NSNull()
    case let .string(s):
      return s
    case let .int(i):
      return i
    case let .double(d):
      return d
    case let .bool(b):
      return b
    case let .array(arr):
      return arr.map { encodeJSONValue($0) }
    case let .object(obj):
      var dict: [String: Any] = [:]
      for (k, v) in obj { dict[k] = encodeJSONValue(v) }
      return dict
    }
  }

  private static let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
}
