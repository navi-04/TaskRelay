package com.naveenraj.taskrelay

import android.content.Context
import android.content.pm.PackageManager

object AppInfo {
    /** versionName from the manifest (sent as X-App-Version, shown by Dart). */
    fun versionName(ctx: Context): String = try {
        ctx.applicationContext.packageManager.getPackageInfo(ctx.applicationContext.packageName, 0).versionName ?: "0"
    } catch (_: PackageManager.NameNotFoundException) {
        "0"
    }
}
