/*
 * PyrxSynapseHostApiImpl.kt
 * pyrx_synapse_android — Pigeon HostApi implementation.
 *
 * Implements the Pigeon-generated PyrxSynapseHostApi interface by
 * forwarding every method to the published synapse-core / synapse-push
 * SDKs (Pyrx.* and PyrxPush.*). Every Pigeon callback runs through a
 * single per-plugin CoroutineScope so the suspend functions on Pyrx
 * (which serialize through internal Mutex) don't compete with each
 * other.
 *
 * Error mapping mirrors the iOS impl + the RN Android bridge:
 *
 *   PyrxError.NotInitialized       → "not_initialized"
 *   PyrxError.InvalidConfig        → "invalid_argument"
 *   PyrxError.Network              → "network_error"
 *   PyrxError.StorageFailure       → "internal_error"
 *   PyrxError.AlreadyInitialized   → "invalid_argument"
 *   <anything else>                → "internal_error"
 *
 * Permission flow
 * ---------------
 * Pyrx (Android) has no requestPushPermission method itself — Android
 * 13+ POST_NOTIFICATIONS is a runtime permission that requires an
 * Activity. The plugin owns this dance: pre-Android 13 returns
 * "granted" immediately; Android 13+ checks current permission state,
 * else calls ActivityCompat.requestPermissions and resolves the Pigeon
 * completion handler from onRequestPermissionsResult below.
 *
 * On configurations without a foreground Activity (the bridge attached
 * before the customer's MainActivity is up) the impl returns
 * "notDetermined" so the caller can retry from a screen.
 */

package tech.pyrx.synapse.flutter

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import tech.pyrx.synapse.LogLevel
import tech.pyrx.synapse.Pyrx
import tech.pyrx.synapse.PyrxConfig
import tech.pyrx.synapse.PyrxEnvironment
import tech.pyrx.synapse.PyrxError
import tech.pyrx.synapse.flutter.generated.FlutterError
import tech.pyrx.synapse.flutter.generated.PyrxDebugInfo as PigeonPyrxDebugInfo
import tech.pyrx.synapse.flutter.generated.PyrxIdentityResult as PigeonPyrxIdentityResult
import tech.pyrx.synapse.flutter.generated.PyrxInitArgs
import tech.pyrx.synapse.flutter.generated.PyrxPushPermissionResult
import tech.pyrx.synapse.flutter.generated.PyrxSynapseHostApi
import tech.pyrx.synapse.identity.IdentityResult
import tech.pyrx.synapse.network.JSONValue
import tech.pyrx.synapse.PyrxDebugInfo as NativePyrxDebugInfo

internal class PyrxSynapseHostApiImpl(
    private val appContext: Context,
) : PyrxSynapseHostApi {

    /// One scope per plugin instance. SupervisorJob means a failed
    /// dispatch doesn't cancel sibling work; Dispatchers.Default keeps
    /// us off the UI thread for SDK calls (the SDK is suspend-safe).
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val json = Json { ignoreUnknownKeys = true }

    /// Activity reference for permission requests, set by the plugin
    /// via setActivity() when ActivityAware fires.
    @Volatile
    private var activity: Activity? = null

    private var pendingPermissionCallback: ((Result<PyrxPushPermissionResult>) -> Unit)? = null

    internal fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    // ----------------------------------------------------------------
    // Lifecycle
    // ----------------------------------------------------------------

    override fun initialize(
        args: PyrxInitArgs,
        callback: (Result<Unit>) -> Unit,
    ) {
        val workspaceUuid = runCatching { UUID.fromString(args.workspaceId) }
            .getOrElse {
                callback(failure("invalid_argument", "workspaceId must be a UUID v4 string"))
                return
            }

        val environment = when (args.environment.lowercase()) {
            "production", "live" -> PyrxEnvironment.PRODUCTION
            "sandbox", "staging", "test" -> PyrxEnvironment.SANDBOX
            else -> {
                callback(failure("invalid_argument", "environment must be one of: production, sandbox"))
                return
            }
        }

        val logLevel = parseLogLevel(args.logLevel) ?: LogLevel.INFO

        val config = PyrxConfig(
            workspaceId = workspaceUuid,
            apiKey = args.apiKey,
            environment = environment,
            baseUrl = args.baseUrl ?: PyrxConfig.DEFAULT_BASE_URL,
            logLevel = logLevel,
            sdkVariant = "flutter",
        )

        scope.launch {
            try {
                Pyrx.initialize(context = appContext, config = config)
                callback(Result.success(Unit))
            } catch (e: PyrxError) {
                callback(Result.failure(translate(e)))
            } catch (e: Throwable) {
                callback(failure("internal_error", e.message ?: e.toString()))
            }
        }
    }

    override fun setLogLevel(
        level: String,
        callback: (Result<Unit>) -> Unit,
    ) {
        val parsed = parseLogLevel(level)
        if (parsed == null) {
            callback(failure("invalid_argument", "level must be one of: debug, info, warning, error, none"))
            return
        }
        Pyrx.setLogLevel(parsed)
        callback(Result.success(Unit))
    }

    override fun debugInfo(callback: (Result<PigeonPyrxDebugInfo>) -> Unit) {
        scope.launch {
            try {
                val info = Pyrx.debugInfo()
                callback(Result.success(encodeDebugInfo(info)))
            } catch (e: Throwable) {
                callback(failure("internal_error", e.message ?: e.toString()))
            }
        }
    }

    // ----------------------------------------------------------------
    // Identity
    // ----------------------------------------------------------------

    override fun identify(
        externalId: String,
        traitsJson: String?,
        callback: (Result<PigeonPyrxIdentityResult>) -> Unit,
    ) {
        val traits = try {
            decodeTraits(traitsJson)
        } catch (e: Throwable) {
            callback(failure("invalid_argument", "traits is not valid JSON: ${e.message}"))
            return
        }
        scope.launch {
            try {
                val result = Pyrx.identify(externalId = externalId, traits = traits)
                callback(Result.success(encodeIdentity(result)))
            } catch (e: PyrxError) {
                callback(Result.failure(translate(e)))
            } catch (e: Throwable) {
                callback(failure("internal_error", e.message ?: e.toString()))
            }
        }
    }

    override fun alias(
        newExternalId: String,
        callback: (Result<PigeonPyrxIdentityResult>) -> Unit,
    ) {
        scope.launch {
            try {
                val result = Pyrx.alias(newExternalId = newExternalId)
                callback(Result.success(encodeIdentity(result)))
            } catch (e: PyrxError) {
                callback(Result.failure(translate(e)))
            } catch (e: Throwable) {
                callback(failure("internal_error", e.message ?: e.toString()))
            }
        }
    }

    override fun logout(callback: (Result<Unit>) -> Unit) {
        scope.launch {
            try {
                Pyrx.logout()
                callback(Result.success(Unit))
            } catch (e: PyrxError) {
                callback(Result.failure(translate(e)))
            } catch (e: Throwable) {
                callback(failure("internal_error", e.message ?: e.toString()))
            }
        }
    }

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    override fun track(
        eventName: String,
        propertiesJson: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val properties = try {
            decodeTraits(propertiesJson)
        } catch (e: Throwable) {
            callback(failure("invalid_argument", "properties is not valid JSON: ${e.message}"))
            return
        }
        scope.launch {
            try {
                Pyrx.track(eventName = eventName, properties = properties)
                callback(Result.success(Unit))
            } catch (e: PyrxError) {
                callback(Result.failure(translate(e)))
            } catch (e: Throwable) {
                callback(failure("internal_error", e.message ?: e.toString()))
            }
        }
    }

    override fun screen(
        screenName: String,
        propertiesJson: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val properties = try {
            decodeTraits(propertiesJson)
        } catch (e: Throwable) {
            callback(failure("invalid_argument", "properties is not valid JSON: ${e.message}"))
            return
        }
        scope.launch {
            try {
                Pyrx.screen(screenName = screenName, properties = properties)
                callback(Result.success(Unit))
            } catch (e: PyrxError) {
                callback(Result.failure(translate(e)))
            } catch (e: Throwable) {
                callback(failure("internal_error", e.message ?: e.toString()))
            }
        }
    }

    // ----------------------------------------------------------------
    // Push
    // ----------------------------------------------------------------

    override fun requestPushPermission(
        alert: Boolean,
        sound: Boolean,
        badge: Boolean,
        callback: (Result<PyrxPushPermissionResult>) -> Unit,
    ) {
        // Pre-Android 13: notification permission granted at install
        // when the customer's app manifest declares POST_NOTIFICATIONS
        // (typically pulled in by synapse-push's transitive
        // dependencies). Report granted unconditionally.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            callback(Result.success(PyrxPushPermissionResult("granted")))
            return
        }
        val alreadyGranted = ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (alreadyGranted) {
            callback(Result.success(PyrxPushPermissionResult("granted")))
            return
        }
        val act = activity
        if (act == null) {
            // No foreground Activity to anchor the OS dialog. Caller
            // can re-request once their UI is mounted.
            callback(Result.success(PyrxPushPermissionResult("notDetermined")))
            return
        }
        pendingPermissionCallback = callback
        ActivityCompat.requestPermissions(
            act,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            PUSH_PERMISSION_REQUEST_CODE,
        )
    }

    override fun registerForPushNotifications(callback: (Result<Unit>) -> Unit) {
        // FCM auto-registers via PyrxMessagingService (installed by
        // PyrxPush.install at plugin attach). No-op on Android.
        callback(Result.success(Unit))
    }

    /**
     * Called from the plugin's ActivityAware permission listener.
     * Returns true if we consumed the result, false if it was for
     * another permission request.
     */
    internal fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PUSH_PERMISSION_REQUEST_CODE) return false
        val callback = pendingPermissionCallback ?: return true
        pendingPermissionCallback = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val status = if (granted) "granted" else "denied"
        callback(Result.success(PyrxPushPermissionResult(status)))
        return true
    }

    // ----------------------------------------------------------------
    // Privacy
    // ----------------------------------------------------------------

    override fun setTrackingEnabled(
        enabled: Boolean,
        callback: (Result<Unit>) -> Unit,
    ) {
        scope.launch {
            try {
                Pyrx.setTrackingEnabled(enabled = enabled)
                callback(Result.success(Unit))
            } catch (e: Throwable) {
                callback(failure("internal_error", e.message ?: e.toString()))
            }
        }
    }

    override fun deleteUser(callback: (Result<Unit>) -> Unit) {
        scope.launch {
            try {
                Pyrx.deleteUser()
                callback(Result.success(Unit))
            } catch (e: PyrxError) {
                callback(Result.failure(translate(e)))
            } catch (e: Throwable) {
                callback(failure("internal_error", e.message ?: e.toString()))
            }
        }
    }

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------

    private fun parseLogLevel(level: String?): LogLevel? =
        when (level?.lowercase()) {
            null, "info" -> LogLevel.INFO
            "debug" -> LogLevel.DEBUG
            "warning", "warn" -> LogLevel.WARNING
            "error" -> LogLevel.ERROR
            "none", "off", "silent" -> LogLevel.NONE
            else -> null
        }

    private fun logLevelString(level: LogLevel): String = when (level) {
        LogLevel.DEBUG -> "debug"
        LogLevel.INFO -> "info"
        LogLevel.WARNING -> "warning"
        LogLevel.ERROR -> "error"
        LogLevel.NONE -> "none"
    }

    private fun decodeTraits(raw: String?): Map<String, JSONValue>? {
        if (raw.isNullOrEmpty()) return null
        // JSONValueSerializer in synapse-core handles per-value
        // discrimination; deserializing into the map directly relies
        // on the kotlinx.serialization Map<String, JSONValue> path.
        return json.decodeFromString(
            kotlinx.serialization.serializer<Map<String, JSONValue>>(),
            raw,
        )
    }

    private fun encodeIdentity(result: IdentityResult): PigeonPyrxIdentityResult =
        PigeonPyrxIdentityResult(
            contactId = result.contactId,
            path = result.path.name.lowercase(),
            aliasedExternalId = result.aliasedExternalId,
            eventsReattributed = result.eventsReattributed.toLong(),
            devicesReattributed = result.devicesReattributed.toLong(),
        )

    private fun encodeDebugInfo(info: NativePyrxDebugInfo): PigeonPyrxDebugInfo {
        // The Android PyrxDebugInfo exposes hasExternalId as a Boolean
        // (not the value itself) -- privacy by default. The Pigeon
        // contract carries externalId as String?, so we project to null
        // on Android and surface only the "has it" bit through a side
        // channel in PR-2's umbrella when the customer-facing debug
        // viewer needs it.
        return PigeonPyrxDebugInfo(
            sdkVersion = info.sdkVersion,
            platform = info.platform,
            initialized = info.initialized,
            workspaceId = info.workspaceId?.toString(),
            environment = info.environment,
            baseUrl = info.baseUrl,
            logLevel = logLevelString(info.logLevel),
            anonymousId = info.anonymousId,
            externalId = null,
            trackingEnabled = info.trackingEnabled,
            queueDepth = info.eventQueueDepth.toLong(),
            deviceTokenFingerprint = info.deviceTokenFingerprint,
        )
    }

    private fun translate(error: PyrxError): FlutterError = when (error) {
        is PyrxError.NotInitialized ->
            FlutterError("not_initialized", "Pyrx.initialize has not completed", null)
        is PyrxError.InvalidConfig ->
            FlutterError("invalid_argument", error.reason, null)
        is PyrxError.Network ->
            FlutterError("network_error", error.inner.toString(), null)
        is PyrxError.StorageFailure ->
            FlutterError("internal_error", "storage failure on ${error.operation}", null)
        is PyrxError.AlreadyInitialized ->
            FlutterError(
                "invalid_argument",
                "Pyrx.initialize was called twice with different configs",
                null,
            )
    }

    private fun <T> failure(code: String, message: String?): Result<T> =
        Result.failure(FlutterError(code, message, null))

    companion object {
        private const val PUSH_PERMISSION_REQUEST_CODE = 0x50_59_52_58 // "PYRX"
    }
}
