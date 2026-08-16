package com.bxzlik.bloom

import android.app.Activity
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Системные диалоги файлов: файл пресетов (SAF) и добавление своих треков.
 *
 * Почему SAF, а не MediaStore (как у скачанных треков): пресеты — не медиа, их
 * место выбирает человек, и никаких разрешений на память для этого не нужно ни
 * на одной версии Android. Своим трекам это тоже подходит: `ACTION_OPEN_DOCUMENT`
 * даёт доступ к ОДНОМУ выбранному файлу, а не ко всей памяти телефона, и
 * `READ_MEDIA_AUDIO` спрашивать не приходится.
 *
 * Ответ канала держим до `onActivityResult`: диалог системный, и результат
 * приходит только оттуда. Второй запрос, пока первый висит, отбиваем — иначе
 * первый `MethodChannel.Result` остался бы без ответа, а это падение в Dart.
 */
class FilesChannel(private val activity: Activity) {

    private var pending: MethodChannel.Result? = null
    private var pendingContent: String? = null

    /** Что делать с выбранным аудио: `inPlace` — помнить путь, `copy` — копия. */
    private var audioMode = MODE_IN_PLACE
    private var audioTracksDir = ""
    private var audioCoversDir = ""

    /** Ключи уже добавленных треков — их не копируем и не разбираем. */
    private var audioKnown = HashSet<String>()

    /** Предложить сохранить текст файлом. Ответ — true/false. */
    fun saveText(
        filename: String,
        content: String,
        mime: String,
        result: MethodChannel.Result,
    ) {
        if (!claim(result)) return
        pendingContent = content
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            putExtra(Intent.EXTRA_TITLE, filename)
        }
        start(intent, REQ_SAVE)
    }

    /** Дать выбрать файл и вернуть его текст. */
    fun openText(result: MethodChannel.Result) {
        if (!claim(result)) return
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // Свой тип у `.bloompresets` не зарегистрирован, и по
            // `application/json` система такой файл НЕ покажет — берём любой,
            // а формат проверит уже Dart, разбирая содержимое.
            type = "*/*"
        }
        start(intent, REQ_OPEN)
    }

    /**
     * Дать выбрать свои аудиофайлы и вернуть готовые записи треков.
     *
     * Всё тяжёлое делаем здесь, а не в Dart: копирование, чтение тегов и
     * вытаскивание обложки. Через канал едут только строки — байты файла и
     * картинки остаются на диске.
     */
    fun pickAudio(
        mode: String,
        tracksDir: String,
        coversDir: String,
        known: List<String>,
        result: MethodChannel.Result,
    ) {
        if (!claim(result)) return
        audioMode = mode
        audioTracksDir = tracksDir
        audioCoversDir = coversDir
        audioKnown = HashSet(known)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // Тип широкий, а список допустимых — в EXTRA_MIME_TYPES: часть
            // провайдеров отдаёт flac и opus как «двоичный файл», и по одному
            // `audio/*` такие файлы были бы не выбираемы.
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, AUDIO_MIME)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        start(intent, REQ_AUDIO)
    }

    /**
     * Вернуть системе разрешение на чужой файл — трек удалили из библиотеки.
     *
     * Нужно не для порядка: число постоянных разрешений у приложения ограничено
     * (на Android 11+ это 512), и без возврата добавление-удаление рано или
     * поздно упёрлось бы в потолок.
     */
    fun releaseAudio(uri: String, result: MethodChannel.Result) {
        try {
            activity.contentResolver.releasePersistableUriPermission(
                Uri.parse(uri),
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: Exception) {
            // Разрешения уже нет — ровно то, чего мы и добивались.
        }
        result.success(null)
    }

    /** `false` — предыдущий диалог ещё не ответил, этот запрос отбит. */
    private fun claim(result: MethodChannel.Result): Boolean {
        if (pending != null) {
            result.error("busy", "диалог файла уже открыт", null)
            return false
        }
        pending = result
        return true
    }

    private fun start(intent: Intent, request: Int) {
        try {
            activity.startActivityForResult(intent, request)
        } catch (e: Exception) {
            finish { it.error("dialog", e.message ?: "нет проводника файлов", null) }
        }
    }

    /** Вернуть результат в Dart и забыть про запрос. */
    private fun finish(answer: (MethodChannel.Result) -> Unit) {
        val result = pending ?: return
        pending = null
        pendingContent = null
        answer(result)
    }

    /**
     * Обработать ответ системного диалога. `true` — код наш, дальше по цепочке
     * его передавать не нужно.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQ_AUDIO) {
            val uris = if (resultCode == Activity.RESULT_OK) pickedUris(data) else emptyList()
            // Отмена — не ошибка: Dart отличает её по null.
            if (uris.isEmpty()) {
                finish { it.success(null) }
            } else {
                importAudio(uris)
            }
            return true
        }
        if (requestCode != REQ_SAVE && requestCode != REQ_OPEN) return false
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            // Отмена — не ошибка: Dart отличает её по false/null.
            finish { if (requestCode == REQ_SAVE) it.success(false) else it.success(null) }
            return true
        }
        try {
            if (requestCode == REQ_SAVE) {
                val content = pendingContent.orEmpty()
                activity.contentResolver.openOutputStream(uri, "wt")?.use { out ->
                    out.write(content.toByteArray(Charsets.UTF_8))
                } ?: throw IllegalStateException("не удалось открыть файл на запись")
                finish { it.success(true) }
            } else {
                val text = activity.contentResolver.openInputStream(uri)?.use { input ->
                    input.readBytes().toString(Charsets.UTF_8)
                } ?: throw IllegalStateException("не удалось прочитать файл")
                finish { it.success(text) }
            }
        } catch (e: Exception) {
            finish { it.error("io", e.message ?: "ошибка файла", null) }
        }
        return true
    }

    /** Выбранные файлы: один в `data`, несколько — в `clipData`. */
    private fun pickedUris(data: Intent?): List<Uri> {
        if (data == null) return emptyList()
        val clip = data.clipData
        if (clip != null) {
            return (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
        }
        return listOfNotNull(data.data)
    }

    /**
     * Разобрать выбранное и ответить в Dart. Своим потоком: копирование файла
     * и чтение тегов — это диск, а мы стоим на главном потоке, с которого
     * рисуется приложение.
     */
    private fun importAudio(uris: List<Uri>) {
        val mode = audioMode
        val tracksDir = File(audioTracksDir)
        val coversDir = File(audioCoversDir)
        val known = audioKnown
        Thread {
            val out = ArrayList<HashMap<String, Any?>>()
            for (uri in uris) {
                try {
                    val entry = importOne(uri, mode, tracksDir, coversDir, known)
                    if (entry != null) out.add(entry)
                } catch (_: Exception) {
                    // Не-аудио и нечитаемое пропускаем молча, как `add_files`
                    // на десктопе: человек выбрал пачку, и падать из-за одного
                    // файла в ней неправильно.
                }
            }
            activity.runOnUiThread { finish { it.success(out) } }
        }.start()
    }

    /** `null` — файл уже в библиотеке либо это не аудио. */
    private fun importOne(
        uri: Uri,
        mode: String,
        tracksDir: File,
        coversDir: File,
        known: HashSet<String>,
    ): HashMap<String, Any?>? {
        val name = displayName(uri)
        val size = fileSize(uri)

        // «На месте» держится на постоянном разрешении: без него `content://`
        // умрёт вместе с текущим запуском. Не дали — честно копируем, иначе
        // трек молча перестал бы играть после перезапуска.
        val persisted = mode == MODE_IN_PLACE && takePersistable(uri)
        val key = if (persisted) uri.toString() else "$name|$size"
        // Ключ добавляем сразу: он же отсекает дубли ВНУТРИ одной пачки.
        if (!known.add(key)) return null

        var copy: File? = null
        if (!persisted) {
            copy = copyInto(tracksDir, uri, name) ?: run {
                known.remove(key)
                return null
            }
        }

        val retriever = MediaMetadataRetriever()
        try {
            if (copy != null) {
                retriever.setDataSource(copy.absolutePath)
            } else {
                retriever.setDataSource(activity, uri)
            }
            val entry = HashMap<String, Any?>()
            entry["key"] = key
            entry["name"] = name
            entry["size"] = size
            if (persisted) entry["uri"] = uri.toString() else entry["file"] = copy?.name
            entry["durationMs"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L
            entry["title"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
            // У сборников исполнитель трека пуст, а альбомный заполнен — на ПК
            // тот же порядок (`artist` → `AlbumArtist`).
            entry["artist"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                    ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)
            entry["album"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
            entry["year"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR)
                    ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)
            entry["genre"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_GENRE)
            entry["cover"] = saveCover(retriever.embeddedPicture, coversDir)
            return entry
        } catch (e: Exception) {
            // Файл не открылся как аудио — копию за собой убираем.
            copy?.delete()
            known.remove(key)
            throw e
        } finally {
            retriever.release()
        }
    }

    /** Постоянное разрешение на чтение чужого файла. `false` — не дали. */
    private fun takePersistable(uri: Uri): Boolean = try {
        activity.contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
        )
        true
    } catch (_: Exception) {
        false
    }

    private fun displayName(uri: Uri): String {
        activity.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getString(0)
            }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "audio"
    }

    private fun fileSize(uri: Uri): Long {
        activity.contentResolver
            .query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getLong(0)
            }
        return 0L
    }

    /** Копия внутри приложения. `null` — скопировать не вышло. */
    private fun copyInto(dir: File, uri: Uri, name: String): File? = try {
        dir.mkdirs()
        val dest = uniqueFile(dir, safeName(name))
        activity.contentResolver.openInputStream(uri)?.use { input ->
            dest.outputStream().use { out -> input.copyTo(out) }
        } ?: throw IllegalStateException("не удалось прочитать файл")
        dest
    } catch (_: Exception) {
        null
    }

    /** `Song.mp3`, `Song (2).mp3`, `Song (3).mp3`… — как `unique_file` на ПК. */
    private fun uniqueFile(dir: File, name: String): File {
        var candidate = File(dir, name)
        if (!candidate.exists()) return candidate
        val stem = name.substringBeforeLast('.', name)
        val ext = name.substringAfterLast('.', "").let { if (it.isEmpty()) "" else ".$it" }
        var n = 2
        while (candidate.exists()) {
            candidate = File(dir, "$stem ($n)$ext")
            n++
        }
        return candidate
    }

    private fun safeName(name: String): String {
        val clean = name.replace(Regex("""[\\/:*?"<>|]+"""), "_").trim()
        return if (clean.isEmpty()) "audio" else clean.take(120)
    }

    /** Встроенная обложка файлом в `covers/`; `null` — её в тегах нет. */
    private fun saveCover(bytes: ByteArray?, dir: File): String? {
        if (bytes == null || bytes.isEmpty()) return null
        return try {
            dir.mkdirs()
            // Расширение честное только по имени: картинку Flutter узнаёт по
            // самим байтам (в тегах это почти всегда JPEG).
            val name = "lt_${System.currentTimeMillis()}_${coverSeq++}.jpg"
            File(dir, name).writeBytes(bytes)
            name
        } catch (_: Exception) {
            null
        }
    }

    /** Разводит имена обложек, записанных в одну миллисекунду. */
    private var coverSeq = 0

    private companion object {
        const val REQ_SAVE = 1101
        const val REQ_OPEN = 1102
        const val REQ_AUDIO = 1103

        const val MODE_IN_PLACE = "inPlace"

        val AUDIO_MIME = arrayOf(
            "audio/*",
            // Контейнеры, которые провайдеры нередко отдают не как аудио.
            "application/ogg",
            "application/x-flac",
            "application/octet-stream",
        )
    }
}
