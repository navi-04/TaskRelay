package com.naveenraj.taskrelay

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.provider.Settings
import android.telecom.TelecomManager
import android.util.Log
import java.io.ByteArrayOutputStream

/**
 * The apps the user can pick as distractions, and the ones that can NEVER be picked.
 *
 * Launchable apps come from `queryIntentActivities(MAIN + LAUNCHER)`, which needs only a `<queries>` entry in the manifest (not
 * QUERY_ALL_PACKAGES, which Play restricts). The list and the icons are only ever handed to the Flutter UI on this device; they are
 * never sent anywhere else.
 *
 * Protected = Settings, the phone / dialer, emergency, contacts, the installer and permission screens, System UI, TaskRelay itself,
 * and (resolved on THIS device, see [protectedExtras]) every launcher, every enabled keyboard and the default dialer: blocking any
 * of those could lock the user out of their own phone.
 */
object InstalledApps {
    data class App(val packageName: String, val label: String) {
        fun toMap(): Map<String, Any?> = mapOf("package" to packageName, "label" to label)
    }

    const val OWN_PACKAGE = "com.naveenraj.taskrelay"

    /** The fixed part of the protected set. The device-specific part (launchers, keyboards, dialer) comes from [protectedExtras]. */
    val PROTECTED: Set<String> = setOf(
        OWN_PACKAGE,
        "com.android.settings",
        "com.android.systemui",
        "com.android.phone",
        "com.android.dialer",
        "com.google.android.dialer",
        "com.android.emergency",
        "com.android.contacts",
        "com.google.android.contacts",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.google.android.permissioncontroller",
        "com.android.permissioncontroller",
    )

    private const val TAG = "InstalledApps"
    private const val ICON_PX = 96

    /** PURE: can [pkg] never be blocked? [extra] is [protectedExtras] (empty in pure callers). */
    fun isProtected(pkg: String, extra: Set<String> = emptySet()): Boolean = pkg in PROTECTED || pkg in extra

    /** PURE: the packages named by an `ENABLED_INPUT_METHODS` / `DEFAULT_INPUT_METHOD` value (`pkg/.Service[;subtype]:pkg2/...`). */
    fun inputMethodPackages(setting: String?): Set<String> =
        setting.orEmpty().split(':').mapNotNull { id -> id.substringBefore('/', "").trim().takeIf { it.isNotEmpty() } }.toSet()

    /** PURE: [raw] without the protected apps, one entry per package, sorted by label (case-insensitive, then package). */
    fun curate(raw: List<App>, extra: Set<String> = emptySet()): List<App> =
        raw.filter { !isProtected(it.packageName, extra) }
            .distinctBy { it.packageName }
            .map { if (it.label.isBlank()) it.copy(label = it.packageName) else it }
            .sortedWith(compareBy<App, String>(String.CASE_INSENSITIVE_ORDER) { it.label }.thenBy { it.packageName })

    // ── device queries ───────────────────────────────────────────────────────────────────────────────────────────

    /** Launchable apps the user may pick, sorted by label. Slow (a package-manager query per app): call it off the main thread. */
    fun list(ctx: Context): List<App> {
        val pm = ctx.applicationContext.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        // The APPLICATION's label (what [label] gives the block screen), not the label of whichever launcher activity came first.
        val raw = queryActivities(pm, launcher).map { App(it.activityInfo.packageName, it.activityInfo.applicationInfo.loadLabel(pm).toString()) }
        return curate(raw, protectedExtras(ctx))
    }

    /** The protected packages that depend on this device: TaskRelay, every launcher, the enabled keyboards, the default dialer. */
    fun protectedExtras(ctx: Context): Set<String> {
        val app = ctx.applicationContext
        val out = HashSet<String>()
        out.add(app.packageName)
        out.addAll(homePackages(app))
        out.addAll(keyboardPackages(app))
        try {
            (app.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager)?.defaultDialerPackage?.let { out.add(it) }
        } catch (t: Throwable) {
            Log.w(TAG, "default dialer unknown: ${t.javaClass.simpleName}")
        }
        return out
    }

    /** Every app that can be the home screen (the manifest's `<queries>` lists the HOME intent, so Android 11+ shows them to us). */
    fun homePackages(ctx: Context): Set<String> = try {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        queryActivities(ctx.applicationContext.packageManager, home).map { it.activityInfo.packageName }.toSet()
    } catch (t: Throwable) {
        Log.w(TAG, "launchers unknown: ${t.javaClass.simpleName}")
        emptySet()
    }

    /** The enabled input methods plus the default one (read from the secure settings: no package visibility needed). */
    fun keyboardPackages(ctx: Context): Set<String> = try {
        val cr = ctx.applicationContext.contentResolver
        inputMethodPackages(Settings.Secure.getString(cr, Settings.Secure.ENABLED_INPUT_METHODS)) +
            inputMethodPackages(Settings.Secure.getString(cr, Settings.Secure.DEFAULT_INPUT_METHOD))
    } catch (t: Throwable) {
        Log.w(TAG, "keyboards unknown: ${t.javaClass.simpleName}")
        emptySet()
    }

    /** The label of [pkg] for the block screen, or null when it is unknown (uninstalled, or hidden from us). */
    fun label(ctx: Context, pkg: String): String? = try {
        val pm = ctx.applicationContext.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString().takeIf { it.isNotBlank() }
    } catch (_: Throwable) {
        null
    }

    /** [pkg]'s launcher icon as a PNG of at most 96 x 96 px, or null when the package is unknown. Slow: call it off the main thread. */
    fun appIcon(ctx: Context, pkg: String): ByteArray? = try {
        val icon = ctx.applicationContext.packageManager.getApplicationIcon(pkg)
        val bitmap = Bitmap.createBitmap(ICON_PX, ICON_PX, Bitmap.Config.ARGB_8888)
        try {
            icon.setBounds(0, 0, ICON_PX, ICON_PX)
            icon.draw(Canvas(bitmap))
            ByteArrayOutputStream().use { out -> if (bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) out.toByteArray() else null }
        } finally {
            bitmap.recycle()
        }
    } catch (_: Throwable) {
        null
    }

    private fun queryActivities(pm: PackageManager, intent: Intent): List<ResolveInfo> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }
}
