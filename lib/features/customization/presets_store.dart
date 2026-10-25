/// Пресеты кастомизации — порт десктопного `presetsStore.ts`.
///
/// Пресет это снимок контекстов: какая картинка стояла фоном, какая обложкой,
/// какая ползунком, — с размытием и затемнением фона и режимом обложки на
/// момент сохранения. По желанию (тумблеры при создании) в него же ложатся
/// тема, прозрачность и шрифт
///
/// Картинки хранятся как `id` картинки библиотеки, а не сама картинка —
/// как на ПК, и по той же причине: копия данных раздула бы хранилище и
/// пережила бы удаление картинки из библиотеки (см. [purgeImage]).
///
/// Экспорт разворачивает id в самодостаточный файл (`.bloompresets`), импорт
/// кладёт картинки обратно в библиотеку и проставляет свежие id — тоже с ПК.
/// Отличие в том, ЧТО едет в файле: на десктопе это `data:`-строка целиком, у
/// нас — либо http(s)-ссылка как есть, либо картинка, закодированная base64
/// (файл-то на телефоне свой, чужому устройству он ни о чём не говорит).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/cover_store.dart';
import '../../core/store/json_store.dart' show jsonStoreProvider;
import '../../core/store/settings_store.dart';
import '../settings/transparency_store.dart';
import 'custom_store.dart';
import 'media_store.dart';

/// Столько же, сколько на десктопе.
const int kPresetsLimit = 20;

/// Метка формата файла — по ней импорт отличает свой файл от чужого JSON.
const String kPresetsKind = 'bloom-presets';

class Preset {
  const Preset({
    required this.id,
    required this.name,
    this.bg,
    this.cover,
    this.slider,
    this.blur,
    this.dim,
    this.coverMode,
    this.theme,
    this.transparency,
    this.font,
    this.ts = 0,
  });

  final String id;
  final String name;

  /// Поля — id картинок библиотеки.
  final String? bg;
  final String? cover;
  final String? slider;

  /// Размытие и затемнение фона на момент сохранения. Живут они в самой
  /// картинке ([MediaItem.blur]), и без снимка пресет брал бы то, что у неё
  /// сейчас. `null` — пресет старый (снимка не было): применение не трогает
  /// то, что стоит у картинки.
  final double? blur;
  final double? dim;

  /// Режим обложки на момент сохранения — только если обложка в пресете есть.
  final CoverMode? coverMode;

  /// Тема, прозрачность и шрифт — по желанию, тумблерами при создании. На ПК
  /// в пресете их нет: это наше расширение, десктоп эти поля файла пропустит.
  final ThemePreset? theme;
  final Transparency? transparency;
  final String? font;

  final int ts;

  CustomTargets get targets =>
      CustomTargets(bg: bg, cover: cover, slider: slider);

  bool get hasImages => bg != null || cover != null || slider != null;

  /// Пресет, в котором не осталось ничего, — такой не сохраняем, не
  /// импортируем и удаляем, когда из него ушла последняя картинка.
  bool get isEmpty =>
      !hasImages && theme == null && transparency == null && font == null;

  /// id всех картинок пресета, в порядке карточек на странице картинки.
  List<String> get imageIds => [?bg, ?cover, ?slider];

  Preset scrub(String imageId) {
    final keepBg = bg != imageId;
    final keepCover = cover != imageId;
    return Preset(
      id: id,
      name: name,
      bg: keepBg ? bg : null,
      cover: keepCover ? cover : null,
      slider: slider == imageId ? null : slider,
      blur: keepBg ? blur : null,
      dim: keepBg ? dim : null,
      coverMode: keepCover ? coverMode : null,
      theme: theme,
      transparency: transparency,
      font: font,
      ts: ts,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (bg != null) 'bg': bg,
    if (cover != null) 'cover': cover,
    if (slider != null) 'slider': slider,
    ...extrasToJson(),
    'ts': ts,
  };

  /// Всё, кроме картинок, — общее для хранилища и файла экспорта.
  Map<String, dynamic> extrasToJson() => {
    if (blur != null) 'blur': blur,
    if (dim != null) 'dim': dim,
    if (coverMode != null) 'coverMode': coverMode!.name,
    // Формат общий с ПК: цвета строками `#rrggbb`, режим прозрачности и как
    // `on`, и как десктопный `trMode`.
    if (theme != null)
      'theme': {
        'id': theme!.id,
        'name': theme!.name,
        'bg': _hex(theme!.bg),
        'blockColor': _hex(theme!.blockColor),
        'accent': _hex(theme!.accent),
        'custom': theme!.custom,
      },
    if (transparency != null)
      'transparency': {
        ...transparency!.toJson(),
        'trMode': transparency!.on ? 'on' : 'off',
      },
    if (font != null) 'font': font,
  };

  static Preset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    String? field(String key) {
      final value = raw[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final name = raw['name'];
    final ts = raw['ts'];
    final extras = PresetExtras.fromJson(raw);
    final preset = Preset(
      id: id,
      name: name is String ? name : '',
      bg: field('bg'),
      cover: field('cover'),
      slider: field('slider'),
      blur: extras.blur,
      dim: extras.dim,
      coverMode: extras.coverMode,
      theme: extras.theme,
      transparency: extras.transparency,
      font: extras.font,
      ts: ts is num ? ts.toInt() : 0,
    );
    return preset.isEmpty ? null : preset;
  }
}

/// Поля пресета помимо картинок, разобранные из хранилища или файла. Битое
/// поле молча выпадает — пресет от этого не ломается.
class PresetExtras {
  const PresetExtras({
    this.blur,
    this.dim,
    this.coverMode,
    this.theme,
    this.transparency,
    this.font,
  });

  final double? blur;
  final double? dim;
  final CoverMode? coverMode;
  final ThemePreset? theme;
  final Transparency? transparency;
  final String? font;

  static PresetExtras fromJson(Map<dynamic, dynamic> raw) {
    final blur = raw['blur'];
    final dim = raw['dim'];
    final mode = raw['coverMode'];
    final tr = raw['transparency'];
    final font = raw['font'];
    return PresetExtras(
      blur: blur is num ? blur.toDouble().clamp(0, kBgBlurMax) : null,
      dim: dim is num ? dim.toDouble().clamp(0, kBgDimMax) : null,
      coverMode: switch (mode) {
        'always' => CoverMode.always,
        'fallback' => CoverMode.fallback,
        _ => null,
      },
      theme: _themeFromJson(raw['theme']),
      transparency: tr is Map ? Transparency.fromJson(tr) : null,
      font: font is String && font.isNotEmpty ? font : null,
    );
  }
}

/// Тема из снимка. Цвета — `#rrggbb` (так их пишут обе стороны) или число
/// ARGB (так их хранит `ThemePreset`); встроенную тему от своей отличает флаг
/// `custom`.
ThemePreset? _themeFromJson(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'];
  final name = raw['name'];
  final bg = _color(raw['bg']);
  final blockColor = _color(raw['blockColor']);
  final accent = _color(raw['accent']);
  if (id is! String || id.isEmpty) return null;
  if (bg == null || blockColor == null || accent == null) return null;
  return ThemePreset(
    id: id,
    name: name is String ? name : '',
    bg: bg,
    blockColor: blockColor,
    accent: accent,
    custom: raw['custom'] != false,
  );
}

Color? _color(Object? raw) {
  if (raw is num) return Color(raw.toInt());
  if (raw is! String) return null;
  final hex = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(raw)?.group(1);
  return hex == null ? null : Color(0xFF000000 | int.parse(hex, radix: 16));
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

final presetsProvider = NotifierProvider<PresetsController, List<Preset>>(
  PresetsController.new,
);

class PresetsController extends Notifier<List<Preset>> {
  static const _key = 'presets';

  @override
  List<Preset> build() => [
    for (final raw in ref.read(jsonStoreProvider).readList(_key))
      ?Preset.fromJson(raw),
  ];

  /// Снимок текущего вида: картинки контекстов с размытием, затемнением и
  /// режимом обложки, а по флагам — тема, прозрачность и шрифт. `null` —
  /// сохранять нечего или упёрлись в лимит.
  Preset? save(
    String name, {
    bool theme = false,
    bool transparency = false,
    bool font = false,
  }) {
    if (state.length >= kPresetsLimit) return null;
    final targets = ref.read(customProvider);
    final bgItem = ref.read(customItemProvider(CustomCtx.bg));
    final settings = ref.read(settingsProvider);
    final preset = Preset(
      id: 'pr${DateTime.now().millisecondsSinceEpoch}_${_seq++}',
      name: name.trim(),
      bg: targets.bg,
      cover: targets.cover,
      slider: targets.slider,
      blur: bgItem?.blur,
      dim: bgItem?.dim,
      coverMode: targets.cover == null ? null : ref.read(coverModeProvider),
      theme: theme ? settings.preset : null,
      transparency: transparency ? ref.read(transparencyProvider) : null,
      font: font ? settings.fontFamily : null,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    if (preset.isEmpty) return null;
    state = [...state, preset];
    _save();
    return preset;
  }

  /// Применить: заданные контексты ставим, пустые НЕ трогаем — как
  /// `applyPreset` на десктопе. Остальное из снимка возвращаем, только если
  /// оно в пресете есть.
  void apply(String id) {
    final preset = byId(id);
    if (preset == null) return;
    ref.read(customProvider.notifier).applyTargets(preset.targets);
    final lib = ref.read(mediaLibProvider.notifier);
    if (preset.bg case final bg?) {
      if (preset.blur case final blur?) lib.setBlur(bg, blur);
      if (preset.dim case final dim?) lib.setDim(bg, dim);
    }
    if (preset.coverMode case final mode?) {
      ref.read(coverModeProvider.notifier).set(mode);
    }
    final settings = ref.read(settingsProvider.notifier);
    if (preset.theme case final theme?) settings.restoreTheme(theme);
    if (preset.transparency case final tr?) {
      ref.read(transparencyProvider.notifier).restore(tr);
    }
    if (preset.font case final font?) settings.setFontFamily(font);
  }

  void delete(String id) {
    state = [
      for (final preset in state)
        if (preset.id != id) preset,
    ];
    _save();
  }

  Preset? byId(String id) {
    for (final preset in state) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  /// Каскад при удалении картинки: убрать ссылки на неё, опустевшие пресеты
  /// удалить (десктопный `purgeImage`). Пресет с темой, прозрачностью или
  /// шрифтом без картинок не пуст — он остаётся.
  void purgeImage(String imageId) {
    final next = <Preset>[];
    var changed = false;
    for (final preset in state) {
      final scrubbed = preset.scrub(imageId);
      if (scrubbed.bg != preset.bg ||
          scrubbed.cover != preset.cover ||
          scrubbed.slider != preset.slider) {
        changed = true;
      }
      if (scrubbed.isEmpty) {
        changed = true;
        continue;
      }
      next.add(scrubbed);
    }
    if (!changed) return;
    state = next;
    _save();
  }

  /// Дописать импортированные пресеты (с учётом лимита). Возвращает, сколько
  /// реально добавилось.
  int addAll(List<Preset> presets) {
    final room = kPresetsLimit - state.length;
    if (room <= 0 || presets.isEmpty) return 0;
    final taken = presets.take(room).toList();
    state = [...state, ...taken];
    _save();
    return taken.length;
  }

  void _save() => ref.read(jsonStoreProvider).write(_key, [
    for (final preset in state) preset.toJson(),
  ]);
}

int _seq = 0;

// ─── Файл `.bloompresets` ───────────────────────────────────────────────────

/// Собрать содержимое файла: id картинок разворачиваются в сами картинки —
/// ссылкой (как есть) или `data:`-строкой, если картинка лежит у нас файлом.
///
/// base64 тяжёлый, поэтому разворот идёт ТОЛЬКО в файл экспорта: внутри
/// приложения по-прежнему ходят id.
Future<String> encodePresets(List<Preset> presets, List<MediaItem> lib) async {
  final byId = {for (final item in lib) item.id: item};
  final out = <Map<String, dynamic>>[];
  for (final preset in presets) {
    Future<String?> data(String? id) async {
      final item = id == null ? null : byId[id];
      if (item == null) return null;
      if (!item.isLocal) return item.src;
      final path = localCoverPath(item.src);
      if (path == null) return null;
      try {
        final bytes = await File(path).readAsBytes();
        return 'data:${_mimeOf(item.name)};base64,${base64Encode(bytes)}';
      } catch (_) {
        return null; // файла уже нет — пресет уедет без этой картинки
      }
    }

    final entry = <String, dynamic>{
      'name': preset.name,
      'ts': preset.ts,
      'bg': await data(preset.bg),
      'cover': await data(preset.cover),
      'slider': await data(preset.slider),
      // Размытие и затемнение — ключи десктопного файла; у старого пресета
      // снимка нет, и берём то, что стоит у картинки.
      'blur': _numOf(preset.blur ?? byId[preset.bg]?.blur),
      'dim': _numOf(preset.dim ?? byId[preset.bg]?.dim),
    }..removeWhere((_, value) => value == null);
    final hasImages =
        entry['bg'] != null ||
        entry['cover'] != null ||
        entry['slider'] != null;
    // Режим обложки, тема, прозрачность и шрифт — наши поля: ПК их пропустит.
    final extras = preset.extrasToJson()
      ..remove('blur')
      ..remove('dim');
    if (!hasImages) {
      // Без картинок у пресета остаётся только вид — без него он пуст.
      extras.remove('coverMode');
      if (extras.isEmpty) continue;
    }
    out.add({...entry, ...extras});
  }
  return const JsonEncoder.withIndent('  ').convert({
    'kind': kPresetsKind,
    'version': 1,
    'exportedAt': DateTime.now().millisecondsSinceEpoch,
    'presets': out,
  });
}

double? _numOf(double? value) => value == null || value == 0 ? null : value;

String _mimeOf(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

/// Разобрать файл и завести из него пресеты: картинки уезжают в библиотеку,
/// поля пресета получают их свежие id. Возвращает, сколько пресетов добавилось
/// (0 — файл не наш, пуст или всё упёрлось в лимит).
Future<int> importPresets(ReadProvider read, String content) async {
  final parsed = decodePresets(content);
  if (parsed.isEmpty) return 0;
  final lib = read(mediaLibProvider.notifier);
  final out = <Preset>[];
  for (final entry in parsed) {
    final name = entry.name.isEmpty ? 'preset' : entry.name;
    // Размытие и затемнение — свойство КАРТИНКИ фона, поэтому едут с ней, а не
    // с пресетом: у нас эти ручки живут на странице картинки.
    final bg = entry.bg == null
        ? null
        : await lib.ensureImage(
            entry.bg!,
            name: name,
            blur: entry.blur,
            dim: entry.dim,
          );
    final cover = entry.cover == null
        ? null
        : await lib.ensureImage(entry.cover!, name: name);
    final slider = entry.slider == null
        ? null
        : await lib.ensureImage(entry.slider!, name: name);
    final extras = entry.extras;
    final preset = Preset(
      id: 'pr${DateTime.now().millisecondsSinceEpoch}_${_seq++}',
      name: entry.name,
      bg: bg,
      cover: cover,
      slider: slider,
      blur: bg == null ? null : entry.blur,
      dim: bg == null ? null : entry.dim,
      coverMode: cover == null ? null : extras.coverMode,
      theme: extras.theme,
      transparency: extras.transparency,
      font: extras.font,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    if (!preset.isEmpty) out.add(preset);
  }
  return read(presetsProvider.notifier).addAll(out);
}

/// Разобранный пресет из файла: картинки ещё не в библиотеке.
class ImportedPreset {
  const ImportedPreset({
    required this.name,
    this.bg,
    this.cover,
    this.slider,
    this.blur = 0,
    this.dim = 0,
    this.extras = const PresetExtras(),
  });

  final String name;

  /// Сами картинки: `data:`-строка либо http(s)-ссылка.
  final String? bg;
  final String? cover;
  final String? slider;
  final double blur;
  final double dim;

  /// Режим обложки, тема, прозрачность, шрифт — наши поля файла.
  final PresetExtras extras;

  bool get isEmpty =>
      bg == null &&
      cover == null &&
      slider == null &&
      extras.theme == null &&
      extras.transparency == null &&
      extras.font == null;
}

/// Разобрать файл. Пустой список — файл не наш или в нём нет пресетов
/// (десктопные `presets.toast.importBad` / `importEmpty`).
///
/// Как и на ПК, принимаем и обёртку `{kind, presets}`, и голый массив: файл
/// могли собрать руками.
List<ImportedPreset> decodePresets(String content) {
  Object? parsed;
  try {
    parsed = jsonDecode(content);
  } catch (_) {
    return const [];
  }
  final raw = parsed is Map ? parsed['presets'] : parsed;
  if (raw is! List) return const [];
  final out = <ImportedPreset>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    String? image(String key) {
      final value = entry[key];
      if (value is! String || value.isEmpty) return null;
      return value.startsWith('data:') || isImageUrl(value) ? value : null;
    }

    final name = entry['name'];
    final blur = entry['blur'];
    final dim = entry['dim'];
    final preset = ImportedPreset(
      name: name is String ? name.trim() : '',
      bg: image('bg'),
      cover: image('cover'),
      slider: image('slider'),
      blur: blur is num ? blur.toDouble().clamp(0, kBgBlurMax) : 0,
      dim: dim is num ? dim.toDouble().clamp(0, kBgDimMax) : 0,
      extras: PresetExtras.fromJson(entry),
    );
    if (!preset.isEmpty) out.add(preset);
  }
  return out;
}
