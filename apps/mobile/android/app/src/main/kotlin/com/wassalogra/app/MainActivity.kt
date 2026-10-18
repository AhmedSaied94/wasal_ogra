package com.wassalogra.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Dart reports when الموقف first draws, so cold start is measured to a usable
        // screen rather than to the splash (FR-012a, research R13).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LAUNCH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "reportFullyDrawn" -> {
                        reportFullyDrawn()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        const val LAUNCH_CHANNEL = "wassal/launch"
    }
}
