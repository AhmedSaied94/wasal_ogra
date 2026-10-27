package com.wassalogra.app

import android.os.SystemClock
import android.provider.Settings
import com.google.android.gms.auth.blockstore.Blockstore
import com.google.android.gms.auth.blockstore.RetrieveBytesRequest
import com.google.android.gms.auth.blockstore.StoreBytesData
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Dart reports when الموقف first draws, so cold start is measured to a usable
        // screen rather than to the splash (FR-012a, research R13).
        MethodChannel(messenger, LAUNCH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "reportFullyDrawn" -> {
                        reportFullyDrawn()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Trusted time counts with the uptime counter, which no clock change
        // moves, and the boot count tells a restart apart
        // (specs/007-m05-local-economy, research R9). No permission needed.
        MethodChannel(messenger, CLOCK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bootSnapshot" -> result.success(
                        mapOf(
                            "elapsed_realtime_ms" to SystemClock.elapsedRealtime(),
                            "boot_count" to bootCount(),
                        ),
                    )
                    else -> result.notImplemented()
                }
            }
        // The install id in Block Store, which keeps it across a re-install
        // on the same phone (specs/011-m06-identity-sync, research R1). Dart
        // falls back to wassal_install.xml. A read that fails answers an
        // error, not null, so Dart never writes a new id over one it
        // couldn't read; a write that fails answers false.
        MethodChannel(messenger, INSTALL_ID_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> readInstallId(result)
                    "write" -> when (val id = call.argument<String>("id")) {
                        null -> result.success(false)
                        else -> writeInstallId(id, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readInstallId(result: MethodChannel.Result) {
        try {
            val request = RetrieveBytesRequest.Builder()
                .setKeys(listOf(INSTALL_ID_KEY))
                .build()
            Blockstore.getClient(this).retrieveBytes(request)
                .addOnSuccessListener { response ->
                    val data = response.blockstoreDataMap[INSTALL_ID_KEY]
                    result.success(data?.bytes?.toString(Charsets.UTF_8))
                }
                .addOnFailureListener { result.error(READ_FAILED, null, null) }
        } catch (e: Exception) {
            result.error(READ_FAILED, null, null)
        }
    }

    // Cloud backup only when Block Store can encrypt it end to end;
    // otherwise the value stays on the phone.
    private fun writeInstallId(id: String, result: MethodChannel.Result) {
        try {
            val client = Blockstore.getClient(this)
            client.isEndToEndEncryptionAvailable
                .addOnCompleteListener { check ->
                    val encrypted = check.isSuccessful && check.result == true
                    val data = StoreBytesData.Builder()
                        .setKey(INSTALL_ID_KEY)
                        .setBytes(id.toByteArray(Charsets.UTF_8))
                        .setShouldBackupToCloud(encrypted)
                        .build()
                    client.storeBytes(data)
                        .addOnSuccessListener { result.success(true) }
                        .addOnFailureListener { result.success(false) }
                }
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun bootCount(): Int? =
        try {
            Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT)
        } catch (e: Settings.SettingNotFoundException) {
            null
        }

    private companion object {
        const val LAUNCH_CHANNEL = "wassal/launch"
        const val CLOCK_CHANNEL = "wassal/clock"
        const val INSTALL_ID_CHANNEL = "wassal/install_id"
        const val INSTALL_ID_KEY = "com.wassalogra.install_id"
        const val READ_FAILED = "read_failed"
    }
}
