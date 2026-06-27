/*
 * PyrxSynapsePlugin.kt
 * pyrx_synapse_android — Android implementation of the PYRX Synapse Flutter SDK.
 *
 * FlutterPlugin entry point. Flutter invokes onAttachedToEngine() at
 * engine-attach time; we do three things there:
 *
 *   1. Construct a single PyrxSynapseHostApi implementor
 *      (PyrxSynapseHostApiImpl) and install it via the Pigeon-generated
 *      PyrxSynapseHostApi.setUp companion. Any Dart-side
 *      `Synapse.identify(...)` etc. routes through the Pigeon codec to
 *      a method on the impl.
 *
 *   2. Construct a single StreamEventsStreamHandler subclass
 *      (PyrxEventStreamHandler) and register it via the Pigeon-generated
 *      StreamEventsStreamHandler.register companion. The handler
 *      lazy-subscribes to Pyrx.events (a SharedFlow from synapse-core
 *      0.1.4's observer surface added in Phase 9.2.1) when the first
 *      Dart listener attaches, and cancels on the last detach. One
 *      coroutine per plugin instance; multiple Dart subscribers are
 *      fanned out by Flutter's EventChannel.
 *
 *   3. Install PyrxPush so the customer's FCM messages route through
 *      the SDK without manifest edits on their side. `PyrxPush.install`
 *      registers the SDK's FCM receiver and wires the push bridge.
 *
 * ActivityAware
 * -------------
 * We implement ActivityAware because requestPushPermission needs to
 * launch ActivityCompat.requestPermissions, which requires an Activity
 * (the OS permission dialog anchors to it). We track the currently
 * attached Activity so the impl can request permission from a foreground
 * surface; if no Activity is attached the impl falls back to reporting
 * "notDetermined" so the caller can retry from a screen.
 */

package tech.pyrx.synapse.flutter

import android.app.Activity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import tech.pyrx.synapse.flutter.generated.PyrxSynapseHostApi
import tech.pyrx.synapse.flutter.generated.StreamEventsStreamHandler
import tech.pyrx.synapse.push.PyrxPush

class PyrxSynapsePlugin : FlutterPlugin, ActivityAware {

    private var hostApiImpl: PyrxSynapseHostApiImpl? = null
    private var eventStreamHandler: PyrxEventStreamHandler? = null

    // -------------------------------------------------------------------
    // FlutterPlugin
    // -------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val appContext = binding.applicationContext

        // Install the synapse-push FCM bridge. Idempotent and safe to
        // call before Pyrx.initialize — the bridge buffers until the
        // SDK is ready (synapse-push 0.1.4 contract).
        try {
            PyrxPush.install(appContext)
        } catch (e: Throwable) {
            // Don't fail plugin attach if the host app's Firebase
            // setup is incomplete; surface a logcat warning and let
            // the customer's debug call discover the issue.
            android.util.Log.w(
                "PYRXSynapseFlutter",
                "PyrxPush.install failed (FCM not configured?): ${e.message}",
            )
        }

        val impl = PyrxSynapseHostApiImpl(appContext)
        val streamHandler = PyrxEventStreamHandler()
        PyrxSynapseHostApi.setUp(binding.binaryMessenger, impl)
        StreamEventsStreamHandler.register(binding.binaryMessenger, streamHandler)

        hostApiImpl = impl
        eventStreamHandler = streamHandler
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        PyrxSynapseHostApi.setUp(binding.binaryMessenger, null)
        eventStreamHandler?.onCancel(null)
        hostApiImpl = null
        eventStreamHandler = null
    }

    // -------------------------------------------------------------------
    // ActivityAware
    // -------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val activity = binding.activity
        hostApiImpl?.setActivity(activity)
        binding.addRequestPermissionsResultListener { requestCode, _, grantResults ->
            hostApiImpl?.onRequestPermissionsResult(requestCode, grantResults) ?: false
        }
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        hostApiImpl?.setActivity(null as Activity?)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        hostApiImpl?.setActivity(null as Activity?)
    }
}
