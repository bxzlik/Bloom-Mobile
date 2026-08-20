package com.bxzlik.bloom

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.StatFs
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

    /** Системные диалоги файлов (SAF): пресеты кастомизации и свои треки. */
    private val files by lazy { FilesChannel(this) }

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bloom/files",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveText" -> files.saveText(
                    filename = call.argument<String>("filename") ?: "bloom.json",
                    content = call.argument<String>("content").orEmpty(),
                    mime = call.argument<String>("mime") ?: "application/json",
                    result = result,
                )
                "openText" -> files.openText(result)
                // Свои треки: выбор аудио и возврат разрешения на чужой файл.
                "pickAudio" -> files.pickAudio(
                    mode = call.argument<String>("mode") ?: "inPlace",
                    tracksDir = call.argument<String>("tracksDir").orEmpty(),
                    coversDir = call.argument<String>("coversDir").orEmpty(),
                    known = call.argument<List<String>>("known") ?: emptyList(),
                    result = result,
                )
                // Карточка «Итогов» — в системную шторку «Поделиться».
                "shareFile" -> files.shareFile(
                    path = call.argument<String>("path").orEmpty(),
                    mime = call.argument<String>("mime") ?: "image/png",
                    text = call.argument<String>("text"),
                    result = result,
                )
                "releaseAudio" -> files.releaseAudio(
                    uri = call.argument<String>("uri").orEmpty(),
                    result = result,
                )
                // Память телефона — знаменатель кольца в «Хранилище». Считаем
                // по тому тому, где лежат данные приложения: на аппаратах с
                // адаптируемой картой это может быть не системный раздел.
                "diskSpace" -> diskSpace(result)
                // Версия сборки — строка «О приложении». Пакет
                // `package_info_plus` ради двух строк не тянем.
                "appInfo" -> appInfo(result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Ответ системного диалога файла. Своё обрабатываем первыми и только потом
     * зовём `super`: без него плагины (тот же выбор картинки) остались бы без
     * своих результатов.
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (files.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    /**
     * Имя версии и номер сборки из манифеста — `versionName` и `versionCode`
     * (на них же стоит `--build-name`/`--build-number` из workflow сборки).
     */
    private fun appInfo(result: MethodChannel.Result) {
        try {
            val info = packageManager.getPackageInfo(packageName, 0)
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            result.success(mapOf("version" to (info.versionName ?: ""), "build" to code.toString()))
        } catch (e: Exception) {
            // Своего пакета не нашли — такого не бывает, но экран просто
            // покажет прочерк вместо версии.
            result.success(null)
        }
    }

    /** Сколько всего места на томе с данными приложения и сколько свободно. */
    private fun diskSpace(result: MethodChannel.Result) {
        try {
            val stat = StatFs(filesDir.absolutePath)
            result.success(mapOf("total" to stat.totalBytes, "free" to stat.availableBytes))
        } catch (e: Exception) {
            // Тома нет или он не читается — экран просто не покажет долю.
            result.success(null)
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
