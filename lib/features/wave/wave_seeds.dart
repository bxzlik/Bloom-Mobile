/// Подбор сидов — порт `src/wave/seeds.ts`.
///
/// Чистые функции над снимком библиотеки: то, на чём волна строится, целиком
/// определяется тем, что человек слушал и лайкал, — и проверять это удобнее
/// списком, а не на живом сторе.
///
/// Отличие от десктопа: число прослушиваний берётся ТОЛЬКО из истории. На ПК к
/// нему прибавляется `track.playCount`, но там это локальный счётчик, а у нас
/// в этом поле лежит глобальный счётчик площадки (`playback_count` у
/// SoundCloud) — сложив их, мы бы ранжировали библиотеку по чужим
/// прослушиваниям, а не по своим.
library;

import 'dart:math';

import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';

/// Числовой SoundCloud-id трека — по нему и ходит подбор похожих. `null` у
/// всего, что не с SoundCloud: своего движка подбора у остальных площадок нет.
///
/// Разбираем сами, а не через `scNumericId`: тот отдаёт ноль и когда id
/// действительно ноль, и когда разобрать не вышло, — а здесь это разные
/// ответы. Строку возвращаем как есть, без круга через int.
String? scIdOf(Track? track) {
  if (track == null || track.source != MusicSource.soundcloud) return null;
  final tail = track.id.split('_').last;
  return int.tryParse(tail) == null ? null : tail;
}

/// Снимок библиотеки, каким его видит подбор.
class WaveLibrary {
  WaveLibrary({
    required this.lib,
    required this.disliked,
    Iterable<Track> extras = const [],
    Random? random,
  }) : _extras = {for (final t in extras) t.id: t},
       _rnd = random ?? Random();

  final LibraryState lib;

  /// id дизлайкнутых треков — в сиды и в подмешивание они не попадают.
  final Set<String> disliked;

  /// Треки, которых в библиотеке нет, но сидами они быть могут: трек из
  /// выдачи поиска, содержимое очереди, страница артиста. Без них «Волна по
  /// треку» работала бы только для сохранённого.
  final Map<String, Track> _extras;

  final Random _rnd;

  /// Треки библиотеки без дизлайкнутых. Порядок — как в разделе «Все треки».
  late final List<Track> tracks = [
    for (final t in lib.allTracks)
      if (!disliked.contains(t.id)) t,
  ];

  late final Map<String, HistoryEntry> _history = lib.historyById;

  /// Сколько раз трек слушали — из истории, см. заметку в шапке файла.
  int playCount(String trackId) => _history[trackId]?.count ?? 0;

  /// Слушали ли трек за последние [days] дней.
  bool recentlyPlayed(String trackId, int days) {
    final at = _history[trackId]?.at;
    if (at == null) return false;
    return DateTime.now().millisecondsSinceEpoch - at < days * 24 * 3600 * 1000;
  }

  Track? byId(String trackId) => _extras[trackId] ?? lib.tracks[trackId];
}

/// «Волна по треку»: сидом служит он сам.
List<String> pickTrackSeeds(String trackId) => [trackId];

/// «Похожие на очередь» и «Волна по артисту» на SoundCloud: сиды берём из
/// списка равномерно по позициям.
///
///   ≤8 треков → все; 9–15 → 8; 16+ → 10.
///
/// Потолок в десять — цена старта: каждый сид это два запроса к площадке через
/// общую очередь с паузой, а покрытие дальше почти не растёт (выдачи начинают
/// пересекаться).
List<String> pickQueueSeeds(List<String> trackIds, WaveLibrary view) {
  if (trackIds.isEmpty) return const [];

  // Отбираем годные, сохраняя порядок: дизлайкнутые и не-SoundCloud выкидываем
  // ДО расчёта позиций, иначе шаг разъедется.
  final valid = <String>[];
  final seen = <String>{};
  for (final id in trackIds) {
    if (!seen.add(id)) continue;
    if (view.disliked.contains(id)) continue;
    if (scIdOf(view.byId(id)) == null) continue;
    valid.add(id);
  }
  if (valid.isEmpty) return const [];

  final n = valid.length;
  final target = n <= 8
      ? n
      : n <= 15
      ? 8
      : 10;
  if (target >= n) return valid;

  return [
    for (var i = 0; i < target; i++)
      valid[min(n - 1, (i * n / target).round())],
  ];
}

/// «Моя волна»: 3–5 сидов из библиотеки — топ по прослушиваниям, свежие лайки
/// и один трек из любимого жанра.
///
/// [rotation] сдвигает выбор на каждом запуске: без него волна вечно упиралась
/// бы в одни и те же два трека из топа и два последних лайка.
List<String> pickPersonalSeeds(WaveLibrary view, int rotation) {
  final lib = view.tracks;
  if (lib.isEmpty) return const [];

  final seeds = <String>{};

  // 1) Топ по прослушиваниям — два трека со сдвигом.
  final byPlays = _byPlays(view, lib);
  if (byPlays.isNotEmpty) {
    final a = byPlays[(rotation * 2) % byPlays.length];
    final b = byPlays[(rotation * 2 + 1) % byPlays.length];
    seeds.add(a.id);
    seeds.add(b.id);
  }

  // 2) Свежие лайки — тоже со сдвигом.
  final favs = _byFav(view, lib);
  if (favs.isNotEmpty) {
    seeds.add(favs[(rotation * 2) % favs.length].id);
    seeds.add(favs[(rotation * 2 + 1) % favs.length].id);
  }

  // 3) Случайный трек из любимого жанра — он и даёт волне ширину.
  final genre = _topGenre(view, lib, rotation);
  if (genre != null) {
    final candidates = [
      for (final t in lib)
        if (!seeds.contains(t.id) &&
            !view.recentlyPlayed(t.id, 2) &&
            t.genres.any((g) => g.toLowerCase() == genre))
          t,
    ];
    if (candidates.isNotEmpty) {
      seeds.add(candidates[view._rnd.nextInt(candidates.length)].id);
    }
  }

  // Слушать ещё нечего — берём самое свежее в библиотеке.
  if (seeds.isEmpty) {
    for (final t in lib.take(3)) {
      seeds.add(t.id);
    }
  }
  return seeds.take(5).toList();
}

/// Витрина «Моей волны» (кольцо обложек на главной): кандидаты в плитки.
///
/// Близнец [pickPersonalSeeds] — те же источники в том же порядке, но БЕЗ
/// сдвига ротации: отрисовка главной не должна прокручивать карусель сидов
/// настоящей волны. Отдаём с запасом: у части треков обложки не окажется,
/// финальный отбор делает интерфейс.
List<String> pickDisplaySeeds(
  WaveLibrary view,
  int rotation, {
  int limit = 24,
}) {
  final lib = view.tracks;
  if (lib.isEmpty) return const [];

  final out = <String>[];
  final seen = <String>{};
  void push(String? id) {
    if (id == null || out.length >= limit) return;
    if (seen.add(id)) out.add(id);
  }

  final byPlays = _byPlays(view, lib);
  final favs = _byFav(view, lib);
  for (final t in _rotate(byPlays, rotation * 2).take(4)) {
    push(t.id);
  }
  for (final t in _rotate(favs, rotation * 2).take(4)) {
    push(t.id);
  }
  // Добивка: остаток топа → остаток лайков → недавнее → свежее в библиотеке.
  for (final t in byPlays) {
    push(t.id);
  }
  for (final t in favs) {
    push(t.id);
  }
  for (final h in view.lib.history) {
    if (view.disliked.contains(h.trackId)) continue;
    push(h.trackId);
  }
  for (final t in lib) {
    push(t.id);
  }
  return out;
}

/// Знакомые треки для подмешивания в «Мою волну». Перемешаны: одни и те же
/// «знакомые» в каждой пачке звучали бы как сбой, а не как узнавание.
List<Track> pickFamiliarPool(
  WaveLibrary view,
  Set<String> exclude, {
  int limit = 20,
}) {
  final pool = [
    for (final t in view.tracks)
      if (!exclude.contains(t.id) && !view.recentlyPlayed(t.id, 3)) t,
  ];
  pool.shuffle(view._rnd);
  return pool.take(limit).toList();
}

/// Треки с ненулевым числом прослушиваний, сверху — самые слушаемые.
List<Track> _byPlays(WaveLibrary view, List<Track> lib) {
  final scored = [
    for (final t in lib)
      if (view.playCount(t.id) > 0) (t, view.playCount(t.id)),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final x in scored) x.$1];
}

/// Лайкнутые, свежие сверху.
List<Track> _byFav(WaveLibrary view, List<Track> lib) {
  final favs = [
    for (final t in lib)
      if (view.lib.isFav(t.id)) (t, view.lib.favs[t.id] ?? 0),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final x in favs) x.$1];
}

/// Жанр, который человек слушает больше прочих. Вес жанра — сумма
/// прослушиваний его треков.
String? _topGenre(WaveLibrary view, List<Track> lib, int rotation) {
  final score = <String, int>{};
  for (final t in lib) {
    final plays = view.playCount(t.id);
    if (plays <= 0) continue;
    for (final g in t.genres) {
      if (g.isEmpty) continue;
      score.update(g.toLowerCase(), (v) => v + plays, ifAbsent: () => plays);
    }
  }
  if (score.isEmpty) return null;
  final top = score.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final pool = top.take(5).toList();
  return pool[(rotation + view._rnd.nextInt(2)) % pool.length].key;
}

/// Список, прокрученный на [by] позиций.
List<T> _rotate<T>(List<T> items, int by) {
  if (items.length < 2) return items;
  final k = by % items.length;
  return [...items.skip(k), ...items.take(k)];
}
