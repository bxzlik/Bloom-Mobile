/// Заметки к версиям: «Что нового» после обновления и «История обновлений» —
/// порт десктопного `updateStore.ts` в части манифеста (проверка версии живёт
/// отдельно, в `about_store.dart`).
///
/// Манифест — тот же формат, что на ПК: `{"<версия>": {title, date, pages[]}}`,
/// где `title`/`body` могут быть либо строкой, либо парой `{ru, en}`. Лежит он
/// в ЭТОМ же репозитории (`update-notes/update-notes.json`) и тянется по
/// `raw.githubusercontent`: так текст правится и новые версии добавляются без
/// пересборки APK.
///
/// Разобранный манифест кладём в `bloom.json`. Сеть нужна ровно один раз: без
/// неё «История обновлений» открывается из кэша, а не пустым списком.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/log/bloom_log.dart';
import '../../core/store/json_store.dart';
import '../../core/store/library_store.dart' show jsonStoreProvider;
import 'about_store.dart' show compareVersions, kUpdateRepo;

const String _rawBase =
    'https://raw.githubusercontent.com/$kUpdateRepo/main/update-notes/';

Uri get _manifestUrl => Uri.parse('${_rawBase}update-notes.json');

/// Куда в `bloom.json` ложатся кэш манифеста и версия прошлого запуска.
const String kNotesCacheKey = 'updateNotes';
const String _lastRunKey = 'lastRun';

/// Страница заметки: заголовок, текст и, может быть, картинка.
class UpdateNotePage {
  const UpdateNotePage({required this.title, required this.body, this.image});

  final String title;

  /// Текст страницы. Разметка — только списки строками с `- ` в начале, как их
  /// пишет десктопный манифест; рисует их `update_notes_sheet.dart`.
  final String body;

  /// Полная ссылка на картинку или `null`. Имя файла из манифеста
  /// достраивается до `update-notes/assets/<имя>`.
  final String? image;

  bool get isEmpty => title.isEmpty && body.isEmpty && image == null;
}

/// Заметка к одной версии, уже разобранная под текущий язык.
class UpdateNote {
  const UpdateNote({
    required this.version,
    required this.title,
    required this.date,
    required this.pages,
  });

  final String version;
  final String title;

  /// Дата релиза в ISO (`2026-08-20`) или пусто.
  final String date;
  final List<UpdateNotePage> pages;

  /// Есть ли что показывать. Пустую заметку не открываем автоматом — незачем
  /// дёргать человека пустой шторкой.
  bool get hasContent => title.isNotEmpty || pages.any((page) => !page.isEmpty);
}

/// Строка списка «История обновлений».
class NoteHeadline {
  const NoteHeadline({
    required this.version,
    required this.title,
    required this.date,
  });

  final String version;
  final String title;

  /// Дата в ISO — форматируется при показе, чтобы кэш не зависел от языка.
  final String date;
}

/// Как ходим за манифестом. Отдельным провайдером ради тестов — как
/// `releaseFetchProvider` у проверки версии.
typedef NotesFetch = Future<String> Function(Uri url);

final notesFetchProvider = Provider<NotesFetch>((ref) => _get);

Future<String> _get(Uri url) async {
  final res = await http.get(url);
  if (res.statusCode != 200) {
    throw http.ClientException('HTTP ${res.statusCode}', url);
  }
  return res.body;
}

final updateNotesProvider = Provider<UpdateNotes>(UpdateNotes.new);

class UpdateNotes {
  UpdateNotes(this._ref);

  final Ref _ref;

  /// Манифест этой сессии. Держим и промис: «Что нового» при старте и открытая
  /// следом история не должны качать файл дважды.
  Map<String, dynamic>? _manifest;
  Future<Map<String, dynamic>>? _loading;

  JsonStore get _store => _ref.read(jsonStoreProvider);

  /// Версия прошлого запуска; пусто — приложение запускается впервые.
  String get lastRun {
    final raw = _store.readMap(kNotesCacheKey)[_lastRunKey];
    return raw is String ? raw : '';
  }

  /// Запомнить версию этого запуска.
  void markRun(String version) {
    if (version.isEmpty) return;
    final data = Map<String, dynamic>.from(_store.readMap(kNotesCacheKey));
    if (data[_lastRunKey] == version) return;
    data[_lastRunKey] = version;
    _store.write(kNotesCacheKey, data);
  }

  /// Заметка версии или `null`, если её в манифесте нет.
  Future<UpdateNote?> note(String version, String locale) async {
    final manifest = await _load();
    return _note(manifest, version, locale);
  }

  /// Все версии манифеста, новые сверху.
  Future<List<NoteHeadline>> history(String locale) async {
    final manifest = await _load();
    final versions = manifest.keys.toList()
      ..sort((a, b) => compareVersions(b, a));
    return [
      for (final version in versions)
        if (manifest[version] is Map)
          NoteHeadline(
            version: version,
            title: _text((manifest[version] as Map)['title'], locale),
            date: _iso((manifest[version] as Map)['date']),
          ),
    ];
  }

  /// Заметка для авто-показа после обновления — или `null`, если показывать
  /// нечего.
  ///
  /// Молчим в трёх случаях: версия не сменилась; это первый запуск (прошлой
  /// версии не записано — там свой онбординг); в манифесте про эту версию
  /// ничего нет. Отметку о запуске ставим в любом из них: иначе следующий
  /// запуск снова считал бы версию новой.
  Future<UpdateNote?> whatsNew(String version, String locale) async {
    final previous = lastRun;
    markRun(version);
    if (version.isEmpty || previous.isEmpty || previous == version) return null;
    try {
      final fresh = await note(version, locale);
      return fresh != null && fresh.hasContent ? fresh : null;
    } catch (e) {
      // Офлайн после обновления — не беда, «Что нового» откроется руками из
      // «Системы».
      logWarn('notes', 'заметка к версии $version не загрузилась: $e');
      return null;
    }
  }

  /// Манифест: память → сеть → кэш в `bloom.json`.
  Future<Map<String, dynamic>> _load() {
    final cached = _manifest;
    if (cached != null) return Future.value(cached);
    return _loading ??= _fetch()
        .then((manifest) {
          _manifest = manifest;
          return manifest;
        })
        .whenComplete(() => _loading = null);
  }

  Future<Map<String, dynamic>> _fetch() async {
    try {
      final body = await _ref.read(notesFetchProvider)(_manifestUrl);
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException('не JSON-объект');
      final manifest = decoded.cast<String, dynamic>();
      // Версия прошлого запуска лежит в том же ключе — её не затираем.
      final data = Map<String, dynamic>.from(_store.readMap(kNotesCacheKey))
        ..['manifest'] = manifest;
      _store.write(kNotesCacheKey, data);
      return manifest;
    } catch (e) {
      final cached = _store.readMap(kNotesCacheKey)['manifest'];
      if (cached is Map) {
        logWarn('notes', 'манифест не скачался ($e), берём кэш');
        return cached.cast<String, dynamic>();
      }
      rethrow;
    }
  }
}

UpdateNote? _note(
  Map<String, dynamic> manifest,
  String version,
  String locale,
) {
  final raw = manifest[version];
  if (raw is! Map) return null;
  final rawPages = raw['pages'];
  final pages = <UpdateNotePage>[
    if (rawPages is List)
      for (final page in rawPages)
        if (page is Map)
          UpdateNotePage(
            title: _text(page['title'], locale),
            body: _text(page['body'], locale),
            image: _image(page['image']),
          ),
  ];
  return UpdateNote(
    version: version,
    title: _text(raw['title'], locale),
    date: _iso(raw['date']),
    // Старая запись без `pages` (такие есть в десктопном манифесте) — одна
    // страница из `body`.
    pages: pages.isNotEmpty
        ? pages
        : [
            UpdateNotePage(
              title: '',
              body: _text(raw['body'], locale),
              image: null,
            ),
          ],
  );
}

/// Строка под язык: строка — как есть; `{ru, en}` — язык, иначе ru, иначе en.
String _text(Object? raw, String locale) {
  if (raw is String) return raw;
  if (raw is! Map) return '';
  final value = raw[locale] ?? raw['ru'] ?? raw['en'];
  return value is String ? value : '';
}

String _iso(Object? raw) => raw is String ? raw : '';

/// Имя файла → ссылка в `update-notes/assets/`; готовую ссылку не трогаем.
String? _image(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  return '${_rawBase}assets/${raw.replaceAll(RegExp(r'^/+'), '')}';
}

/// ISO-дата → «20 августа 2026» под язык. Кривую дату отдаём как есть — это
/// то же поведение, что у `formatNoteDate` на ПК.
String formatNoteDate(String iso, String locale) {
  if (iso.isEmpty) return '';
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  return DateFormat.yMMMMd(locale).format(date);
}
