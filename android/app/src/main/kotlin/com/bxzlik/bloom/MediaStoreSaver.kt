package com.bxzlik.bloom

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Сохранение скачанного трека в ОБЩУЮ память телефона — «Музыка/Bloom».
 *
 * Это второе из двух скачиваний, как на десктопе: офлайн-копия живёт внутри
 * приложения и видна только Bloom'у, а этот файл кладётся в медиатеку, виден
 * системным плеерам и переживает удаление приложения.
 *
 * Двумя путями, потому что хранилище на Android поменялось на десятке:
 *  - Android 10+ — MediaStore: своя папка внутри Музыки, никаких разрешений;
 *  - раньше — обычный File в публичной папке плюс WRITE_EXTERNAL_STORAGE, и
 *    файл нужно скормить сканеру, иначе плееры его не увидят.
 */
object MediaStoreSaver {

    /** Подпапка внутри «Музыки»: рядом с чужими файлами свои не теряются. */
    private const val FOLDER = "Bloom"

    /**
     * Кладёт [source] в медиатеку под именем [filename].
     *
     * [title]/[artist] пишутся полями медиатеки: у файла с CDN тегов может не
     * быть вовсе, и без этого плееры показали бы «Unknown». Возвращает путь для
     * показа пользователю.
     */
    fun save(
        context: Context,
        source: File,
        filename: String,
        mime: String,
        title: String?,
        artist: String?,
    ): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(context, source, filename, mime, title, artist)
        } else {
            saveViaPublicDir(context, source, filename)
        }
    }

    private fun saveViaMediaStore(
        context: Context,
        source: File,
        filename: String,
        mime: String,
        title: String?,
        artist: String?,
    ): String {
        val resolver = context.contentResolver
        val relative = Environment.DIRECTORY_MUSIC + File.separator + FOLDER
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, filename)
            put(MediaStore.Audio.Media.MIME_TYPE, mime)
            put(MediaStore.Audio.Media.RELATIVE_PATH, relative)
            if (!title.isNullOrEmpty()) put(MediaStore.Audio.Media.TITLE, title)
            if (!artist.isNullOrEmpty()) put(MediaStore.Audio.Media.ARTIST, artist)
            // Пока идёт запись, файл скрыт от остальных приложений: иначе плеер
            // успеет проиндексировать половину трека.
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }

        val collection = MediaStore.Audio.Media.getContentUri(
            MediaStore.VOLUME_EXTERNAL_PRIMARY,
        )
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("медиатека отказала в записи")

        try {
            resolver.openOutputStream(uri).use { out ->
                out ?: throw IllegalStateException("не открылся поток записи")
                source.inputStream().use { it.copyTo(out) }
            }
        } catch (e: Exception) {
            // Недописанный файл не должен остаться висеть в медиатеке.
            resolver.delete(uri, null, null)
            throw e
        }

        values.clear()
        values.put(MediaStore.Audio.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return relative + File.separator + filename
    }

    private fun saveViaPublicDir(
        context: Context,
        source: File,
        filename: String,
    ): String {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
            FOLDER,
        )
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("не создалась папка ${dir.path}")
        }
        val target = uniqueFile(dir, filename)
        source.inputStream().use { input ->
            target.outputStream().use { input.copyTo(it) }
        }
        // Без сканера файл лежит на диске, но в плеерах не появляется.
        MediaScannerConnection.scanFile(context, arrayOf(target.path), null, null)
        return target.path
    }

    /** `Имя.mp3`, `Имя (2).mp3`, … — два трека могут называться одинаково. */
    private fun uniqueFile(dir: File, filename: String): File {
        val dot = filename.lastIndexOf('.')
        val base = if (dot > 0) filename.substring(0, dot) else filename
        val ext = if (dot > 0) filename.substring(dot) else ""
        var candidate = File(dir, filename)
        var i = 2
        while (candidate.exists()) {
            candidate = File(dir, "$base ($i)$ext")
            i++
        }
        return candidate
    }
}
