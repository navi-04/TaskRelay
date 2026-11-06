package com.naveenraj.taskrelay

import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

data class HttpResponse(
    val status: Int,
    /** Header names lower-cased. */
    val headers: Map<String, String>,
    val body: String,
    /** Non-null when no HTTP response was obtained (connect / read timeout, DNS, TLS ...). */
    val ioError: String? = null,
) {
    val isIoError: Boolean get() = ioError != null

    /** `error.code` of a `{error:{code,message}}` body. */
    val errorCode: String?
        get() = errorField("code")

    val errorMessage: String?
        get() = errorField("message")

    private fun errorField(name: String): String? = try {
        JSONObject(body).optJSONObject("error")?.let { Json.str(it, name) }
    } catch (_: Exception) {
        null
    }

    /** Retry-After in seconds (delta-seconds form only), or null. */
    val retryAfterSec: Long?
        get() = headers["retry-after"]?.trim()?.toLongOrNull()?.takeIf { it >= 0 }
}

interface HttpTransport {
    fun execute(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse
}

/** HttpURLConnection, 15 s connect / read timeouts, redirects NOT followed (the bearer token must never follow a redirect). */
object UrlConnectionTransport : HttpTransport {
    private const val TIMEOUT_MS = 15_000
    private const val MAX_BODY_BYTES = 4 * 1024 * 1024

    override fun execute(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse {
        var conn: HttpURLConnection? = null
        try {
            conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = TIMEOUT_MS
                readTimeout = TIMEOUT_MS
                instanceFollowRedirects = false
                useCaches = false
                requestMethod = method
                for ((k, v) in headers) setRequestProperty(k, v)
                if (body != null) {
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                }
            }
            val status = conn.responseCode
            val stream = if (status >= 400) conn.errorStream else conn.inputStream
            val text = try {
                stream?.use { readCapped(it) } ?: ""
            } catch (_: IOException) {
                ""
            }
            val hdrs = HashMap<String, String>()
            for ((k, v) in conn.headerFields) if (k != null && !v.isNullOrEmpty()) hdrs[k.lowercase()] = v.last()
            return HttpResponse(status, hdrs, text)
        } catch (e: IOException) {
            return HttpResponse(0, emptyMap(), "", e.javaClass.simpleName + (e.message?.let { ": $it" } ?: ""))
        } catch (e: RuntimeException) {
            // malformed URL, illegal argument ...: not retryable in any useful way, surfaced as an I/O style failure
            return HttpResponse(0, emptyMap(), "", e.javaClass.simpleName)
        } finally {
            conn?.disconnect()
        }
    }

    private fun readCapped(input: java.io.InputStream): String {
        val out = ByteArrayOutputStream()
        val buf = ByteArray(8192)
        var total = 0
        while (true) {
            val n = input.read(buf)
            if (n < 0) break
            total += n
            if (total > MAX_BODY_BYTES) throw IOException("response too large")
            out.write(buf, 0, n)
        }
        return out.toString("UTF-8")
    }
}
