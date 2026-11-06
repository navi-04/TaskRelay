package com.naveenraj.taskrelay

import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/** Crash-safe whole-file replacement (write temp, fsync, rename). Pure java.io, so it runs in JVM tests too. */
object AtomicFiles {
    @Throws(IOException::class)
    fun write(file: File, bytes: ByteArray) {
        file.absoluteFile.parentFile?.mkdirs()
        val tmp = File(file.absoluteFile.parentFile, file.name + ".tmp")
        FileOutputStream(tmp).use {
            it.write(bytes)
            it.flush()
            it.fd.sync()
        }
        // rename is atomic on Android (POSIX) and replaces the target. Windows (JVM tests only) refuses to replace.
        if (!tmp.renameTo(file)) {
            file.delete()
            if (!tmp.renameTo(file)) throw IOException("Could not replace ${file.name}")
        }
    }

    fun readText(file: File): String? = try {
        if (file.exists()) file.readText(Charsets.UTF_8) else null
    } catch (_: IOException) {
        null
    }
}
