import AVFoundation
import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Канал файла пресетов. Держим ссылкой: он делегат пикера, и без неё его
  /// съел бы ARC ровно в момент показа диалога.
  private var files: FilesChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BloomFiles") {
      files = FilesChannel(registrar: registrar)
    }
  }
}

/// Системные диалоги файлов через `UIDocumentPicker` — iOS-половина канала
/// `bloom/files` (Android-половина живёт в `FilesChannel.kt` и ходит в SAF).
/// Их два: файл пресетов кастомизации и добавление своих треков.
///
/// Выгрузка идёт через временный файл: пикер экспорта отдаёт наружу именно
/// файл, а не строку. Отмена — не ошибка: отвечаем `false`/`nil`, как на
/// Android.
///
/// **Режима «на месте» на iOS нет.** Файл из чужой песочницы живёт под
/// security scope, и чтобы вернуться к нему после перезапуска, нужна закладка
/// (security-scoped bookmark) — а её ещё надо где-то держать и обновлять.
/// Поэтому пикер берётся с `asCopy: true` и свой трек ВСЕГДА копируется внутрь
/// приложения, какой бы режим ни стоял в настройках.
///
/// Лежит здесь, а не отдельным файлом, намеренно: новый файл пришлось бы
/// прописывать в `project.pbxproj` руками, а проверить сборку iOS локально
/// нечем (Mac'а у проекта нет, собирает только CI).
///
/// ВНИМАНИЕ: живьём этот код не гонялся — по той же причине.
class FilesChannel: NSObject, UIDocumentPickerDelegate {

  /// Чего ждём от закрывшегося пикера.
  private enum Kind {
    case save
    case open
    case audio
  }

  private var pending: FlutterResult?
  private var kind = Kind.save
  /// Временный файл выгрузки — удаляем, когда пикер закроется.
  private var exported: URL?

  /// Куда класть свои треки и их обложки и что из этого уже добавлено.
  private var tracksDir = ""
  private var coversDir = ""
  private var known = Set<String>()
  /// Разводит имена обложек, записанных в одну секунду.
  private var coverSeq = 0

  init(registrar: FlutterPluginRegistrar) {
    super.init()
    let channel = FlutterMethodChannel(
      name: "bloom/files",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "saveText":
        self.saveText(
          filename: args["filename"] as? String ?? "bloom.bloompresets",
          content: args["content"] as? String ?? "",
          result: result
        )
      case "openText":
        self.openText(result: result)
      case "pickAudio":
        self.pickAudio(
          tracksDir: args["tracksDir"] as? String ?? "",
          coversDir: args["coversDir"] as? String ?? "",
          known: args["known"] as? [String] ?? [],
          result: result
        )
      case "releaseAudio":
        // Возвращать нечего: на iOS файл всегда наша копия, разрешений на
        // чужие файлы мы не держим. Копию удаляет сам Dart.
        result(nil)
      case "diskSpace":
        // Память телефона — знаменатель кольца в «Хранилище».
        self.diskSpace(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Сколько всего места на томе приложения и сколько свободно; `nil` —
  /// система не ответила, и экран просто не покажет долю.
  private func diskSpace(result: @escaping FlutterResult) {
    guard
      let attrs = try? FileManager.default.attributesOfFileSystem(
        forPath: NSHomeDirectory()
      ),
      let total = (attrs[.systemSize] as? NSNumber)?.int64Value,
      let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value
    else {
      result(nil)
      return
    }
    result(["total": total, "free": free])
  }

  private func topController() -> UIViewController? {
    var top = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  private func saveText(filename: String, content: String, result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "диалог файла уже открыт", details: nil))
      return
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    do {
      try content.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      result(FlutterError(code: "io", message: error.localizedDescription, details: nil))
      return
    }
    pending = result
    kind = .save
    exported = url
    let picker = UIDocumentPickerViewController(forExporting: [url])
    picker.delegate = self
    topController()?.present(picker, animated: true)
  }

  private func openText(result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "диалог файла уже открыт", details: nil))
      return
    }
    pending = result
    kind = .open
    // Своего типа у `.bloompresets` не зарегистрировано — пускаем любой файл,
    // а формат проверит уже Dart, разбирая содержимое (как и на Android).
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item])
    picker.delegate = self
    topController()?.present(picker, animated: true)
  }

  private func pickAudio(
    tracksDir: String,
    coversDir: String,
    known: [String],
    result: @escaping FlutterResult
  ) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "диалог файла уже открыт", details: nil))
      return
    }
    pending = result
    kind = .audio
    self.tracksDir = tracksDir
    self.coversDir = coversDir
    self.known = Set(known)
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [UTType.audio],
      asCopy: true
    )
    picker.allowsMultipleSelection = true
    picker.delegate = self
    topController()?.present(picker, animated: true)
  }

  private func finish(_ value: Any?) {
    guard let result = pending else { return }
    pending = nil
    if let url = exported {
      try? FileManager.default.removeItem(at: url)
      exported = nil
    }
    result(value)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    switch kind {
    case .save:
      finish(true)
    case .open:
      guard let url = urls.first else {
        finish(nil)
        return
      }
      // Файл из чужой песочницы читается только под security scope.
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      finish(try? String(contentsOf: url, encoding: .utf8))
    case .audio:
      if urls.isEmpty {
        finish(nil)
        return
      }
      // Копирование и чтение тегов — это диск, а мы на главном потоке, с
      // которого рисуется приложение.
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self = self else { return }
        let entries = urls.compactMap { self.importAudio($0) }
        DispatchQueue.main.async { self.finish(entries) }
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(kind == .save ? false : nil)
  }

  /// Один выбранный файл → запись трека. `nil` — он уже в библиотеке либо не
  /// читается.
  ///
  /// `asCopy: true` уже положил файл во временный каталог — нам остаётся
  /// перенести его к себе, чтобы система не убрала его из tmp.
  private func importAudio(_ source: URL) -> [String: Any]? {
    let name = source.lastPathComponent
    let attrs = try? FileManager.default.attributesOfItem(atPath: source.path)
    let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
    let key = "\(name)|\(size)"
    // Ключ отсекает и дубли ВНУТРИ одной пачки.
    if known.contains(key) { return nil }
    known.insert(key)

    let dir = URL(fileURLWithPath: tracksDir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dest = uniqueFile(dir: dir, name: safeName(name))
    do {
      try FileManager.default.moveItem(at: source, to: dest)
    } catch {
      // Не перенеслось — пробуем скопировать: tmp мог оказаться на другом томе.
      guard (try? FileManager.default.copyItem(at: source, to: dest)) != nil else {
        known.remove(key)
        return nil
      }
    }

    let asset = AVURLAsset(url: dest)
    var entry: [String: Any] = [
      "key": key,
      "name": name,
      "size": size,
      "file": dest.lastPathComponent,
      "durationMs": Int(CMTimeGetSeconds(asset.duration) * 1000),
    ]
    for item in asset.commonMetadata {
      switch item.commonKey {
      case .some(.commonKeyTitle):
        entry["title"] = item.stringValue
      case .some(.commonKeyArtist), .some(.commonKeyAuthor):
        if entry["artist"] == nil { entry["artist"] = item.stringValue }
      case .some(.commonKeyAlbumName):
        entry["album"] = item.stringValue
      case .some(.commonKeyCreationDate):
        entry["year"] = item.stringValue
      case .some(.commonKeyArtwork):
        if let data = item.dataValue, let cover = saveCover(data) {
          entry["cover"] = cover
        }
      default:
        break
      }
    }
    return entry
  }

  /// Встроенная обложка файлом в `covers/`; `nil` — записать не вышло.
  private func saveCover(_ data: Data) -> String? {
    let dir = URL(fileURLWithPath: coversDir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // Расширение честное только по имени: картинку Flutter узнаёт по самим
    // байтам (в тегах это почти всегда JPEG).
    let name = "lt_\(Int(Date().timeIntervalSince1970))_\(coverSeq).jpg"
    coverSeq += 1
    do {
      try data.write(to: dir.appendingPathComponent(name))
      return name
    } catch {
      return nil
    }
  }

  /// `Song.mp3`, `Song (2).mp3`, `Song (3).mp3`… — как на Android и на ПК.
  private func uniqueFile(dir: URL, name: String) -> URL {
    var candidate = dir.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    let stem = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var n = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      let next = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
      candidate = dir.appendingPathComponent(next)
      n += 1
    }
    return candidate
  }

  private func safeName(_ name: String) -> String {
    let bad = CharacterSet(charactersIn: "\\/:*?\"<>|")
    let clean = name.components(separatedBy: bad).joined(separator: "_")
      .trimmingCharacters(in: .whitespaces)
    return clean.isEmpty ? "audio" : String(clean.prefix(120))
  }
}
