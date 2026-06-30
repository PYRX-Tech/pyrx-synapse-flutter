/*
 * PyrxEventStreamHandler.kt
 * pyrx_synapse_android — bridges Pyrx.events (SharedFlow) into the
 * Pigeon-generated StreamEventsStreamHandler that Flutter's EventChannel
 * machinery routes through.
 *
 * Lifecycle
 * ---------
 * Pigeon invokes onListen(...) when the first Dart subscriber attaches
 * (Flutter's EventChannel.receiveBroadcastStream() triggers it lazily).
 * We launch a collector coroutine that subscribes to Pyrx.events --
 * a SharedFlow from synapse-core 0.1.4 that fans out across collectors
 * with a 16-slot replay buffer and DROP_OLDEST overflow. Each event
 * case is converted into a flat PyrxEventEnvelope wire shape and
 * pushed through the Pigeon sink.
 *
 * Pigeon invokes onCancel(...) when the last Dart subscriber detaches.
 * We cancel the held Job; the SharedFlow collector terminates and the
 * native observer registry GCs the subscription.
 *
 * Why one collector per plugin instance: a SharedFlow already fans out
 * across collectors, so a single collector at the bridge layer
 * forwards every emission to every Dart subscriber without per-listener
 * duplication. The Pigeon sink itself handles the Flutter-side
 * fan-out across multiple Dart Stream subscribers.
 */

package tech.pyrx.synapse.flutter

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import tech.pyrx.synapse.Pyrx
import tech.pyrx.synapse.flutter.generated.IdentityChangedEventDto
import tech.pyrx.synapse.flutter.generated.IdentitySnapshotDto
import tech.pyrx.synapse.flutter.generated.InAppMessageDismissedEventDto
import tech.pyrx.synapse.flutter.generated.InAppMessageReceivedEventDto
import tech.pyrx.synapse.flutter.generated.PigeonEventSink
import tech.pyrx.synapse.flutter.generated.PushClickedEventDto
import tech.pyrx.synapse.flutter.generated.PushReceivedEventDto
import tech.pyrx.synapse.flutter.generated.PyrxEventEnvelope
import tech.pyrx.synapse.flutter.generated.PyrxEventKind
import tech.pyrx.synapse.flutter.generated.QueueDrainedEventDto
import tech.pyrx.synapse.flutter.generated.StreamEventsStreamHandler
import tech.pyrx.synapse.network.JSONValue
import tech.pyrx.synapse.observer.IdentitySnapshot
import tech.pyrx.synapse.observer.PushClickedEvent
import tech.pyrx.synapse.observer.PushReceivedEvent
import tech.pyrx.synapse.observer.PyrxEvent

internal class PyrxEventStreamHandler : StreamEventsStreamHandler() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var collectorJob: Job? = null

    override fun onListen(
        p0: Any?,
        sink: PigeonEventSink<PyrxEventEnvelope>,
    ) {
        collectorJob?.cancel()
        collectorJob = scope.launch {
            Pyrx.events.collect { event ->
                runCatching { sink.success(encode(event)) }
                    .onFailure { t ->
                        android.util.Log.w(
                            "PYRXSynapseFlutter",
                            "event forwarding failed: ${t.message}",
                        )
                    }
            }
        }
    }

    override fun onCancel(p0: Any?) {
        collectorJob?.cancel()
        collectorJob = null
    }

    // ----------------------------------------------------------------
    // Native -> Wire conversion
    // ----------------------------------------------------------------

    private fun encode(event: PyrxEvent): PyrxEventEnvelope = when (event) {
        is PyrxEvent.PushReceived -> PyrxEventEnvelope(
            kind = PyrxEventKind.PUSH_RECEIVED,
            pushReceived = encodePushReceived(event.event),
        )
        is PyrxEvent.PushClicked -> PyrxEventEnvelope(
            kind = PyrxEventKind.PUSH_CLICKED,
            pushClicked = encodePushClicked(event.event),
        )
        is PyrxEvent.PushReceivedColdStart -> PyrxEventEnvelope(
            kind = PyrxEventKind.PUSH_RECEIVED_COLD_START,
            pushReceivedColdStart = encodePushReceived(event.event),
        )
        is PyrxEvent.QueueDrained -> PyrxEventEnvelope(
            kind = PyrxEventKind.QUEUE_DRAINED,
            queueDrained = QueueDrainedEventDto(count = event.count.toLong()),
        )
        is PyrxEvent.IdentityChanged -> PyrxEventEnvelope(
            kind = PyrxEventKind.IDENTITY_CHANGED,
            identityChanged = IdentityChangedEventDto(
                before = event.before?.let { encodeIdentity(it) },
                after = encodeIdentity(event.after),
            ),
        )
        is PyrxEvent.InAppMessageReceived -> PyrxEventEnvelope(
            kind = PyrxEventKind.IN_APP_MESSAGE_RECEIVED,
            inAppMessageReceived = InAppMessageReceivedEventDto(
                message = encodeInAppMessage(event.message),
            ),
        )
        is PyrxEvent.InAppMessageDismissed -> PyrxEventEnvelope(
            kind = PyrxEventKind.IN_APP_MESSAGE_DISMISSED,
            inAppMessageDismissed = InAppMessageDismissedEventDto(
                messageId = event.messageId,
                reason = event.reason,
            ),
        )
    }

    private fun encodePushReceived(p: PushReceivedEvent): PushReceivedEventDto =
        PushReceivedEventDto(
            title = p.title,
            body = p.body,
            pushLogId = p.pushLogId,
            data = mapKeyed(p.userInfo),
            pyrxAttrs = mapKeyed(p.pyrxAttributes),
            receivedAt = p.receivedAt.toString(),
        )

    private fun encodePushClicked(p: PushClickedEvent): PushClickedEventDto =
        PushClickedEventDto(
            pushLogId = p.pushLogId,
            deepLink = p.deepLink,
            actionId = p.actionId,
            pyrxAttrs = mapKeyed(p.pyrxAttributes),
            clickedAt = p.clickedAt.toString(),
        )

    private fun encodeIdentity(s: IdentitySnapshot): IdentitySnapshotDto =
        IdentitySnapshotDto(
            anonymousId = s.anonymousId,
            externalId = s.externalId,
            snapshotAt = s.resolvedAt.toString(),
        )

    /**
     * Project a typed attribute map onto Pigeon's `Map<String?, Any?>`
     * wire shape. Each JSONValue case is decomposed into its primitive;
     * arrays/objects recurse. The app-facing Dart layer (PR-2) re-wraps
     * primitives into the typed PyrxAttributeValue sealed class.
     */
    private fun mapKeyed(src: Map<String, JSONValue>): Map<String?, Any?> {
        val out = HashMap<String?, Any?>(src.size)
        for ((k, v) in src) {
            out[k] = decompose(v)
        }
        return out
    }

    private fun decompose(value: JSONValue): Any? = when (value) {
        is JSONValue.Null -> null
        is JSONValue.Bool -> value.value
        is JSONValue.Int -> value.value
        is JSONValue.Num -> value.value
        is JSONValue.Str -> value.value
        is JSONValue.Arr -> value.value.map { decompose(it) }
        is JSONValue.Obj -> value.value.mapValues { decompose(it.value) }
    }
}
