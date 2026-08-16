/// Библиотека картинок кастомизации — порт десктопного
/// `features/customization/model/mediaLibStore.ts` + `lib/mediaIdb.ts`.
///
/// Отличие от ПК в ХРАНЕНИИ, и оно принципиальное. Там картинка живёт целиком
/// в IndexedDB строкой `data:` — здесь так нельзя: `bloom.json` переписывается
/// целиком на каждую правку, и пара обоев в base64 превратила бы каждое
/// сохранение библиотеки в мегабайты. Поэтому файл копируется в каталог
/// приложения (тот же `covers/`, где лежат свои обложки плейлистов и аватары),
/// а в JSON едет только ссылка `local:<имя файла>` — ровно та схема, которую
/// понимает `coverImage` из `cover_store.dart`. Картинка «по ссылке» хранится
/// самим http(s)-адресом, и та же `coverImage` отдаёт по нему `NetworkImage`.
///
/// Размытие и затемнение — СВОИ У КАЖДОЙ КАРТИНКИ (на ПК это две общие ручки
/// фона). Так выбрал пользователь: страница картинки показывает их рядом с её
/// превью, и обои помнят, какими их настроили, даже пока фоном стоит другое.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/store/cover_store.dart';
import '../../core/store/library_store.dart' show jsonStoreProvider;

/// Границы ползунков страницы картинки — те же, что на десктопе
/// (`BackgroundCards`: blur 0…80 px, dim 0…100 %).
const double kBgBlurMax = 80;
const double kBgDimMax = 100;

/// Картинка библиотеки.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.src,
    this.blur = 0,
    this.dim = 0,
    this.addedAt = 0,
  });

  final String id;

  /// Имя файла или последний сегмент ссылки — подпись под превью.
  final String name;

  /// `local:<имя>` (файл в каталоге приложения) либо http(s)-ссылка. В обоих
  /// случаях разворачивается общей `coverImage`.
  final String src;

  /// Размытие фона, 0…[kBgBlurMax] px. Работает, только когда эта картинка
  /// стоит фоном.
  final double blur;

  /// Затемнение фона, 0…[kBgDimMax] %.
  final double dim;

  final int addedAt;

  bool get isLocal => isLocalCover(src);

  MediaItem copyWith({double? blur, double? dim}) => MediaItem(
    id: id,
    name: name,
    src: src,
    blur: blur ?? this.blur,
    dim: dim ?? this.dim,
    addedAt: addedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'src': src,
    'blur': blur,
    'dim': dim,
    'addedAt': addedAt,
  };

  /// `null` — запись без ссылки на картинку: показывать нечего.
  static MediaItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final src = raw['src'];
    if (id is! String || src is! String || src.isEmpty) return null;
    final name = raw['name'];
    final blur = raw['blur'];
    final dim = raw['dim'];
    final addedAt = raw['addedAt'];
    return MediaItem(
      id: id,
      name: name is String && name.isNotEmpty ? name : 'image',
      src: src,
      blur: blur is num ? blur.toDouble().clamp(0, kBgBlurMax) : 0,
      dim: dim is num ? dim.toDouble().clamp(0, kBgDimMax) : 0,
      addedAt: addedAt is num ? addedAt.toInt() : 0,
    );
  }
}

/// http(s)-ссылка на картинку — десктопный `addUrl` пускает только такие.
bool isImageUrl(String value) =>
    RegExp(r'^https?://.+', caseSensitive: false).hasMatch(value.trim());

/// Имя из ссылки: последний сегмент без параметров запроса.
String urlName(String url) {
  final tail = url.split('/').last.split('?').first;
  return tail.isEmpty ? 'image' : tail;
}

final mediaLibProvider = NotifierProvider<MediaLibController, List<MediaItem>>(
  MediaLibController.new,
);

class MediaLibController extends Notifier<List<MediaItem>> {
  static const _key = 'media';

  @override
  List<MediaItem> build() => [
    for (final raw in ref.read(jsonStoreProvider).readList(_key))
      ?MediaItem.fromJson(raw),
  ];

  MediaItem? byId(String? id) {
    if (id == null) return null;
    for (final item in state) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Выбрать картинки в галерее и положить их к себе. Возвращает, сколько
  /// добавилось (0 — отменили или не дали доступ).
  ///
  /// Размер НЕ ограничиваем и качество не трогаем: `image_picker` с
  /// `maxWidth`/`imageQuality` пережимает картинку в JPEG, и гифка приехала бы
  /// одним кадром — а гифки тут главный смысл (на ПК их отдельно ловит
  /// `isGif`). Обои и так лежат по одной штуке, а не сотнями, как обложки.
  Future<int> addFromGallery() async {
    final List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultiImage(
        requestFullMetadata: kPickMetadata,
      );
    } catch (_) {
      return 0; // отказ в доступе к галерее
    }
    if (picked.isEmpty) return 0;
    final added = <MediaItem>[];
    for (final file in picked) {
      final src = await copyLocalFile(File(file.path), prefix: 'media');
      if (src == null) continue;
      added.add(
        MediaItem(
          id: _genId(),
          name: file.name,
          src: src,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    if (added.isEmpty) return 0;
    state = [...state, ...added];
    _save();
    return added.length;
  }

  /// Добавить по ссылке. `false` — ссылка не похожа на картинку (десктопный
  /// `medialib.toast.badUrl`).
  bool addUrl(String url) {
    final value = url.trim();
    if (!isImageUrl(value)) return false;
    state = [
      ...state,
      MediaItem(
        id: _genId(),
        name: urlName(value),
        src: value,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
    _save();
    return true;
  }

  /// Положить в библиотеку картинку из файла пресета: `data:`-строку пишем
  /// файлом, ссылку кладём как есть. Дубли разводим по `src` — так импорт
  /// одного и того же файла дважды не плодит копии (десктопный `ensureImages`
  /// дедупит по тем же данным).
  ///
  /// Возвращает id картинки в библиотеке; `null` — строку не разобрать.
  Future<String?> ensureImage(
    String data, {
    String name = 'preset',
    double blur = 0,
    double dim = 0,
  }) async {
    String? src;
    var itemName = name;
    if (isImageUrl(data)) {
      src = data.trim();
      itemName = urlName(src);
    } else if (data.startsWith('data:')) {
      final comma = data.indexOf(',');
      if (comma < 0) return null;
      final header = data.substring(5, comma);
      if (!header.contains('base64')) return null;
      try {
        final bytes = base64Decode(data.substring(comma + 1));
        final mime = header.split(';').first;
        src = await saveLocalImage(
          bytes,
          prefix: 'media',
          ext: _extOfMime(mime),
        );
      } catch (_) {
        return null;
      }
    }
    if (src == null) return null;

    for (final item in state) {
      if (item.src == src) return item.id;
    }
    final item = MediaItem(
      id: _genId(),
      name: itemName,
      src: src,
      blur: blur.clamp(0, kBgBlurMax),
      dim: dim.clamp(0, kBgDimMax),
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    state = [...state, item];
    _save();
    return item.id;
  }

  void setBlur(String id, double px) =>
      _patch(id, (item) => item.copyWith(blur: px.clamp(0, kBgBlurMax)));

  void setDim(String id, double pct) =>
      _patch(id, (item) => item.copyWith(dim: pct.clamp(0, kBgDimMax)));

  /// Удалить картинку. Файл с диска тоже уходит, но каскад по контекстам и
  /// пресетам делает не стор, а вызывающая сторона (`removeMedia` в
  /// `custom_store.dart`): сторы про друг друга не знают, как и на десктопе,
  /// где каскад собран в `mediaLibStore.remove`.
  void remove(String id) {
    final item = byId(id);
    if (item == null) return;
    state = [
      for (final other in state)
        if (other.id != id) other,
    ];
    _save();
    if (item.isLocal) unawaited(deleteCover(item.src));
  }

  void _patch(String id, MediaItem Function(MediaItem) f) {
    if (byId(id) == null) return;
    state = [
      for (final item in state)
        if (item.id == id) f(item) else item,
    ];
    _save();
  }

  void _save() => ref.read(jsonStoreProvider).write(_key, [
    for (final item in state) item.toJson(),
  ]);
}

String _extOfMime(String mime) => switch (mime) {
  'image/png' => 'png',
  'image/gif' => 'gif',
  'image/webp' => 'webp',
  _ => 'jpg',
};

/// Счётчик разводит id картинок, добавленных в одну миллисекунду: выбор
/// нескольких файлов разом — обычное дело, а `Random` тут ни к чему.
int _seq = 0;

String _genId() => 'ml${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
