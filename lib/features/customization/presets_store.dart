/// Пресеты кастомизации — порт десктопного `presetsStore.ts`.
///
/// Пресет это снимок контекстов: какая картинка стояла фоном, какая обложкой,
/// какая ползунком. Поля хранят `id` картинки библиотеки, а не саму картинку —
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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/cover_store.dart';
import '../../core/store/library_store.dart' show jsonStoreProvider;
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
    this.ts = 0,
  });

  final String id;
  final String name;

  /// Поля — id картинок библиотеки.
  final String? bg;
  final String? cover;
  final String? slider;
  final int ts;

  CustomTargets get targets =>
      CustomTargets(bg: bg, cover: cover, slider: slider);

  /// Пресет без единой картинки — такой не сохраняем и не импортируем.
  bool get isEmpty => bg == null && cover == null && slider == null;

  /// id всех картинок пресета, в порядке карточек на странице картинки.
  List<String> get imageIds => [?bg, ?cover, ?slider];

  Preset scrub(String imageId) => Preset(
    id: id,
    name: name,
    bg: bg == imageId ? null : bg,
    cover: cover == imageId ? null : cover,
    slider: slider == imageId ? null : slider,
    ts: ts,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (bg != null) 'bg': bg,
    if (cover != null) 'cover': cover,
    if (slider != null) 'slider': slider,
    'ts': ts,
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
    final preset = Preset(
      id: id,
      name: name is String ? name : '',
      bg: field('bg'),
      cover: field('cover'),
      slider: field('slider'),
      ts: ts is num ? ts.toInt() : 0,
    );
    return preset.isEmpty ? null : preset;
  }
}

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

  /// Снимок текущих контекстов. `null` — сохранять нечего (ни одного
  /// применённого контекста) или упёрлись в лимит.
  Preset? save(String name) {
    final targets = ref.read(customProvider);
    if (targets.isEmpty || state.length >= kPresetsLimit) return null;
    final preset = Preset(
      id: 'pr${DateTime.now().millisecondsSinceEpoch}_${_seq++}',
      name: name.trim(),
      bg: targets.bg,
      cover: targets.cover,
      slider: targets.slider,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    state = [...state, preset];
    _save();
    return preset;
  }

  void apply(String id) {
    final preset = byId(id);
    if (preset == null) return;
    ref.read(customProvider.notifier).applyTargets(preset.targets);
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
  /// удалить (десктопный `purgeImage`).
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
      'blur': _numOf(byId[preset.bg]?.blur),
      'dim': _numOf(byId[preset.bg]?.dim),
    }..removeWhere((_, value) => value == null);
    if (entry['bg'] == null &&
        entry['cover'] == null &&
        entry['slider'] == null) {
      continue;
    }
    out.add(entry);
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
    if (bg == null && cover == null && slider == null) continue;
    out.add(
      Preset(
        id: 'pr${DateTime.now().millisecondsSinceEpoch}_${_seq++}',
        name: entry.name,
        bg: bg,
        cover: cover,
        slider: slider,
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
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
  });

  final String name;

  /// Сами картинки: `data:`-строка либо http(s)-ссылка.
  final String? bg;
  final String? cover;
  final String? slider;
  final double blur;
  final double dim;

  bool get isEmpty => bg == null && cover == null && slider == null;
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
    );
    if (!preset.isEmpty) out.add(preset);
  }
  return out;
}
