package com.naveenraj.taskrelay

import android.annotation.SuppressLint
import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The signed-in session (server base URL + bearer token), shared by the Flutter UI and the background sync.
 *
 * The token is encrypted with an AES-256-GCM key that lives in the AndroidKeyStore (alias `taskrelay_session`); the prefs file
 * `taskrelay_session` holds `base64(iv | ciphertext)` plus the plain base URL. The keystore picks a random 12-byte IV per
 * encryption. If decryption ever fails (restored backup, changed keystore, wiped key) the session is treated as signed out and
 * the prefs are cleared. The prefs are excluded from backup (see the manifest).
 */
@SuppressLint("ApplySharedPref") // commit() on purpose: the session must be on disk (or gone) before we return
object SessionStore {
    data class Session(val baseUrl: String, val token: String)

    private const val ALIAS = "taskrelay_session"
    private const val PREFS = "taskrelay_session"
    private const val K_BASE = "base_url"
    private const val K_TOKEN = "token_blob"
    private const val IV_BYTES = 12

    @Synchronized
    fun set(ctx: Context, baseUrl: String, token: String) {
        val blob = encrypt(token)
        check(prefs(ctx).edit().putString(K_BASE, baseUrl).putString(K_TOKEN, blob).commit()) { "could not persist session" }
    }

    /** The session, or null when signed out or when the stored token can no longer be decrypted (the prefs are then cleared). */
    @Synchronized
    fun get(ctx: Context): Session? {
        val p = prefs(ctx)
        val base = p.getString(K_BASE, null)
        val blob = p.getString(K_TOKEN, null)
        if (base.isNullOrEmpty() || blob.isNullOrEmpty()) return null
        return try {
            Session(base, decrypt(blob))
        } catch (_: Exception) {
            clearLocked(ctx)
            null
        }
    }

    /** Cheap check (no keystore call): is there a stored session? */
    fun isSignedIn(ctx: Context): Boolean {
        val p = prefs(ctx)
        return !p.getString(K_BASE, null).isNullOrEmpty() && !p.getString(K_TOKEN, null).isNullOrEmpty()
    }

    @Synchronized
    fun clear(ctx: Context) = clearLocked(ctx)

    private fun clearLocked(ctx: Context) {
        prefs(ctx).edit().clear().commit()
        try {
            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(ALIAS)
        } catch (_: Exception) {
        }
    }

    private fun prefs(ctx: Context) = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    private fun encrypt(plain: String): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        val iv = c.iv
        check(iv.size == IV_BYTES) { "unexpected IV size" }
        val ct = c.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(iv + ct, Base64.NO_WRAP)
    }

    private fun decrypt(blob: String): String {
        val all = Base64.decode(blob, Base64.NO_WRAP)
        require(all.size > IV_BYTES) { "blob too short" }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, all, 0, IV_BYTES))
        return String(c.doFinal(all, IV_BYTES, all.size - IV_BYTES), Charsets.UTF_8)
    }
}
