package com.bxzlik.bloom

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * AudioServiceActivity вместо FlutterActivity — иначе audio_service не сможет
 * поднять активити из уведомления и с экрана блокировки.
 */
class MainActivity : AudioServiceActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bloom/notifications",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Android 13+ прячет шторку воспроизведения без этого
                // разрешения. Диалог показываем и сразу отвечаем: ответ
                // пользователя ни на что в плеере не влияет.
                "ensure" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                        result.success(true)
                    } else {
                        val granted = checkSelfPermission(
                            Manifest.permission.POST_NOTIFICATIONS,
                        ) == PackageManager.PERMISSION_GRANTED
                        if (!granted) {
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQ_NOTIFICATIONS,
                            )
                        }
                        result.success(granted)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        const val REQ_NOTIFICATIONS = 1001
    }
}
