/*
 * InAppEncoders.kt
 * pyrx_synapse_android — shared native-to-wire encoders for the in-app
 * messaging payloads. Phase 10 PR-2b.
 *
 * Both PyrxSynapseHostApiImpl (for the imperative `inAppGetActive`
 * return value) and PyrxEventStreamHandler (for the
 * `inAppMessageReceived` observer envelope) need the same
 * NativeInAppMessage → Pigeon InAppMessageDto conversion. Co-locating
 * the encoder here keeps the two paths in lockstep — a field added to
 * the native shape only needs one edit.
 */

package tech.pyrx.synapse.flutter

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import tech.pyrx.synapse.flutter.generated.InAppCtaDto
import tech.pyrx.synapse.flutter.generated.InAppMessageDto
import tech.pyrx.synapse.inapp.InAppCta as NativeInAppCta
import tech.pyrx.synapse.inapp.InAppCtaActionType as NativeInAppCtaActionType
import tech.pyrx.synapse.inapp.InAppMessage as NativeInAppMessage

/**
 * Convert a native [NativeInAppMessage] into the Pigeon wire DTO. CTAs
 * round-trip via [encodeInAppCta]; `custom` JSON is projected onto a
 * Pigeon `Map<String?, Any?>` (the same shape `pyrx_attrs` uses on
 * push payloads).
 */
internal fun encodeInAppMessage(msg: NativeInAppMessage): InAppMessageDto =
    InAppMessageDto(
        id = msg.id,
        messageId = msg.messageId,
        placement = msg.placement,
        title = msg.title,
        body = msg.body,
        imageUrl = msg.imageUrl,
        ctas = msg.ctas.map(::encodeInAppCta),
        customData = msg.custom?.let(::encodeJsonObject),
        expiresAt = msg.expiresAt,
        priority = msg.priority.toLong(),
    )

internal fun encodeInAppCta(cta: NativeInAppCta): InAppCtaDto =
    InAppCtaDto(
        id = cta.id,
        label = cta.label,
        actionType = when (cta.actionType) {
            NativeInAppCtaActionType.DEEP_LINK -> "deep_link"
            NativeInAppCtaActionType.DISMISS -> "dismiss"
            NativeInAppCtaActionType.WEBVIEW -> "webview"
            NativeInAppCtaActionType.CALLBACK -> "callback"
        },
        actionPayload = cta.actionPayload,
    )

private fun encodeJsonObject(obj: JsonObject): Map<String?, Any?> {
    val out = HashMap<String?, Any?>(obj.size)
    for ((k, v) in obj) {
        out[k] = decomposeJsonElement(v)
    }
    return out
}

private fun decomposeJsonElement(element: JsonElement): Any? = when (element) {
    is JsonNull -> null
    is JsonPrimitive -> {
        // Try int first (kotlinx.serialization keeps the lexical form
        // so int-shaped doubles round-trip as ints), then double, bool,
        // then fall back to string.
        when {
            element.isString -> element.content
            element.booleanOrNull != null -> element.boolean
            element.intOrNull != null -> element.int
            element.doubleOrNull != null -> element.double
            else -> element.content
        }
    }
    is JsonArray -> element.map(::decomposeJsonElement)
    is JsonObject -> {
        val out = HashMap<String, Any?>(element.size)
        for ((k, v) in element) {
            out[k] = decomposeJsonElement(v)
        }
        out
    }
}
