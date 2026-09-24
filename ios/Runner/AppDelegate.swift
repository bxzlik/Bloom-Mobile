import AVFoundation
import Flutter
import MediaPlayer
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
    Nightcore.install()
    NowPlayingLike.install()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BloomFiles") {
      files = FilesChannel(registrar: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BloomNightcore") {
      Nightcore.register(registrar: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BloomLike") {
      NowPlayingLike.register(registrar: registrar)
    }
  }
}

/// Звёздочка «в любимые» на экране блокировки — канал `bloom/like`.
///
/// Своих кнопок iOS в плеер на экране блокировки не пускает, есть только
/// системный `likeCommand`: слева от «назад» он рисуется звёздочкой, `isActive`
/// её заливает. Нарисовать там сердце нельзя — значок выбирает система.
///
/// audio_service своего API для него не даёт и, хуже того, при каждом
/// включении пульта (`activateCommandCenter`, первый play и play после stop)
/// выключает его сам. Поэтому подменяем этот метод: даём плагину отработать и
/// включаем звёздочку обратно.
///
/// Опора на устройство плагина (0.18.19): если метод переименуют, подмена
/// молча не встанет и звёздочки просто не будет — падать тут нечему.
///
/// ВНИМАНИЕ: живьём не гонялось — Mac'а у проекта нет, собирает только CI.
enum NowPlayingLike {
  /// В любимых ли играющий трек и как подписать кнопку — последнее из Dart.
  static var active = false
  static var title = "Like"
  private static var channel: FlutterMethodChannel?
  private static var installed = false

  static func install() {
    guard !installed else { return }
    installed = true
    if let cls = NSClassFromString("AudioServicePlugin"),
      let original = class_getInstanceMethod(cls, NSSelectorFromString("activateCommandCenter")),
      let ours = class_getInstanceMethod(
        NSObject.self,
        #selector(NSObject.bloom_activateCommandCenter)
      ),
      // Кладём свой метод в сам класс плагина и меняем местами уже там: иначе
      // обмен задел бы реализацию на NSObject.
      class_addMethod(
        cls,
        #selector(NSObject.bloom_activateCommandCenter),
        method_getImplementation(ours),
        method_getTypeEncoding(ours)
      ),
      let added = class_getInstanceMethod(cls, #selector(NSObject.bloom_activateCommandCenter))
    {
      method_exchangeImplementations(original, added)
    }
    // Цель вешаем один раз: плагин с `likeCommand` целей не снимает.
    MPRemoteCommandCenter.shared().likeCommand.addTarget { _ in
      channel?.invokeMethod("toggle", arguments: nil)
      return .success
    }
  }

  static func register(registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "bloom/like",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "set", let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      active = args["active"] as? Bool ?? false
      title = args["title"] as? String ?? title
      apply()
      result(nil)
    }
    self.channel = channel
  }

  static func apply() {
    let command = MPRemoteCommandCenter.shared().likeCommand
    command.isEnabled = true
    command.isActive = active
    command.localizedTitle = title
    command.localizedShortTitle = title
  }
}

extension NSObject {
  /// После обмена реализаций вызов `bloom_…` внутри — это исходный метод
  /// плагина.
  @objc dynamic func bloom_activateCommandCenter() {
    bloom_activateCommandCenter()
    NowPlayingLike.apply()
  }
}

/// «Nightcore» на iOS — канал `bloom/nightcore`.
///
/// just_audio на iOS `setPitch` не умеет, а каждому треку ставит
/// `AVAudioTimePitchAlgorithmTimeDomain` — тон сохраняется при любой скорости.
/// Тон, едущий за темпом, у AVFoundation называется `varispeed`, но наружу
/// плагин эту ручку не даёт. Поэтому подменяем два сеттера (swizzling):
/// алгоритм трека — пока nightcore включён, вместо того что просит плагин
/// ставим `varispeed`; скорость плеера — запоминаем плеер и докручиваем
/// алгоритм текущему треку, чтобы тумблер срабатывал не только со следующего.
///
/// Это опора на устройство плагина (0.10.6): если он перестанет звать
/// сеттер алгоритма, nightcore просто замолчит — падать тут нечему.
///
/// ВНИМАНИЕ: живьём не гонялось — Mac'а у проекта нет, собирает только CI.
enum Nightcore {
  /// Включён ли nightcore. Всё на главном потоке: и плагин, и канал.
  static var on = false
  /// Плеер just_audio — узнаём его при первой установке скорости.
  static weak var player: AVPlayer?
  private static var installed = false

  static func install() {
    guard !installed else { return }
    installed = true
    swap(
      AVPlayerItem.self,
      #selector(setter: AVPlayerItem.audioTimePitchAlgorithm),
      #selector(AVPlayerItem.bloom_setAudioTimePitchAlgorithm(_:))
    )
    swap(
      AVPlayer.self,
      #selector(setter: AVPlayer.rate),
      #selector(AVPlayer.bloom_setRate(_:))
    )
  }

  static func register(registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "bloom/nightcore",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "set" else {
        result(FlutterMethodNotImplemented)
        return
      }
      Nightcore.apply(call.arguments as? Bool ?? false)
      result(nil)
    }
  }

  /// Переключить на ходу: переставить алгоритм всем трекам очереди. Через
  /// подменённый сеттер — он сам решит, `varispeed` или `timeDomain`.
  private static func apply(_ value: Bool) {
    guard value != on else { return }
    on = value
    guard let player = player else { return }
    let items = (player as? AVQueuePlayer)?.items() ?? [player.currentItem].compactMap { $0 }
    for item in items {
      item.audioTimePitchAlgorithm = .timeDomain
    }
    // Играющему треку новый алгоритм надёжнее всего подсовывать переустановкой
    // скорости: за `rate` плагин не следит, так что это безопасно.
    if player.rate > 0 {
      player.rate = player.rate
    }
  }

  private static func swap(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
    guard
      let a = class_getInstanceMethod(cls, original),
      let b = class_getInstanceMethod(cls, replacement)
    else { return }
    method_exchangeImplementations(a, b)
  }
}

extension AVPlayerItem {
  /// После обмена реализаций вызов `bloom_…` внутри — это исходный сеттер.
  @objc dynamic func bloom_setAudioTimePitchAlgorithm(_ value: AVAudioTimePitchAlgorithm) {
    bloom_setAudioTimePitchAlgorithm(Nightcore.on ? .varispeed : value)
  }
}

extension AVPlayer {
  /// После обмена реализаций вызов `bloom_…` внутри — это исходный сеттер.
  @objc dynamic func bloom_setRate(_ value: Float) {
    Nightcore.player = self
    if Nightcore.on, value > 0, let item = currentItem,
      item.audioTimePitchAlgorithm != .varispeed
    {
      item.audioTimePitchAlgorithm = .varispeed
    }
    bloom_setRate(value)
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
      case "shareFile":
        // Карточка «Итогов» — в системную шторку. Провайдера, как на Android,
        // здесь не нужно: файл наш и лежит в песочнице приложения.
        self.shareFile(
          path: args["path"] as? String ?? "",
          text: args["text"] as? String,
          result: result
        )
      case "releaseAudio":
        // Возвращать нечего: на iOS файл всегда наша копия, разрешений на
        // чужие файлы мы не держим. Копию удаляет сам Dart.
        result(nil)
      case "diskSpace":
        // Память телефона — знаменатель кольца в «Хранилище».
        self.diskSpace(result: result)
      case "appInfo":
        // Версия сборки — строка «О приложении».
        let info = Bundle.main.infoDictionary
        result([
          "version": info?["CFBundleShortVersionString"] as? String ?? "",
          "build": info?["CFBundleVersion"] as? String ?? "",
        ])
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

  /// Показать `UIActivityViewController` для готового файла.
  ///
  /// Ответ отдаём сразу после показа, как и на Android: что человек выберет в
  /// шторке — не наше дело, а отмена ничем не отличается от отправки.
  ///
  /// `popoverPresentationController` заполняем обязательно: на iPad шторка
  /// показывается поповером и без якоря приложение падает.
  private func shareFile(path: String, text: String?, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path), let top = topController() else {
      result(FlutterError(code: "share", message: "нечего отправлять", details: nil))
      return
    }
    var items: [Any] = [url]
    if let text = text, !text.isEmpty { items.append(text) }
    let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = top.view
      popover.sourceRect = CGRect(
        x: top.view.bounds.midX,
        y: top.view.bounds.midY,
        width: 0,
        height: 0
      )
      popover.permittedArrowDirections = []
    }
    top.present(sheet, animated: true)
    result(true)
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
