package com.wassalogra.app

import android.os.SystemClock
import android.provider.Settings
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
    }
}
