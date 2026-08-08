package com.bxzlik.bloom

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bloom/downloads",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Скачанный трек → общая память («Музыка/Bloom»). Байты уже
                // лежат файлом, который приготовил Dart: гонять мегабайты через
                // канал незачем, хватит пути.
                "save" -> saveToMusic(call, result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Копирует готовый файл в медиатеку. `deleteSource` — про временный файл
     * загрузки: офлайн-копию, наоборот, трогать нельзя, она нужна плееру.
     */
    private fun saveToMusic(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val filename = call.argument<String>("filename")
        if (sourcePath == null || filename == null) {
            result.error("args", "нужны sourcePath и filename", null)
            return
        }
        val source = File(sourcePath)
        if (!source.isFile) {
            result.error("missing", "файла нет: $sourcePath", null)
            return
        }

        // До Android 10 запись в публичную папку требует разрешения. Спрашиваем
        // и честно говорим «повторите»: ответ приходит асинхронно, а держать
        // ради него незавершённый result нельзя.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQ_STORAGE,
            )
            result.error("permission", "нет доступа к памяти телефона", null)
            return
        }

        try {
            val path = MediaStoreSaver.save(
                context = this,
                source = source,
                filename = filename,
                mime = call.argument<String>("mime") ?: "audio/mpeg",
                title = call.argument<String>("title"),
                artist = call.argument<String>("artist"),
            )
            if (call.argument<Boolean>("deleteSource") == true) source.delete()
            result.success(path)
        } catch (e: Exception) {
            result.error("save", e.message ?: "не удалось сохранить", null)
        }
    }

    private companion object {
        const val REQ_NOTIFICATIONS = 1001
        const val REQ_STORAGE = 1002
    }
}
