/// Подбор сидов — порт `src/wave/seeds.ts`.
///
/// Чистые функции над снимком библиотеки: то, на чём волна строится, целиком
/// определяется тем, что человек слушал и лайкал, — и проверять это удобнее
/// списком, а не на живом сторе.
///
/// Число прослушиваний — СВОЁ, из журнала ([PlayStats]), как и на ПК с 3.0.
/// В `track.playCount` у нас лежит глобальный счётчик площадки
/// (`playback_count` у SoundCloud): по нему библиотека ранжировалась бы чужими
/// прослушиваниями, а не своими.
library;

import 'dart:math';

import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_stats.dart';

/// Числовой SoundCloud-id трека — по нему и ходит подбор похожих. `null` у
/// всего, что не с SoundCloud: своего движка подбора у остальных площадок нет.
///
/// Разбираем сами, а не через `scNumericId`: тот отдаёт ноль и когда id
/// действительно ноль, и когда разобрать не вышло, — а здесь это разные
/// ответы. Строку возвращаем как есть, без круга через int.
String? scIdOf(Track? track) {
  if (track == null || track.source != MusicSource.soundcloud) return null;
  final tail = track.id.split(':').last;
  return int.tryParse(tail) == null ? null : tail;
}

/// Снимок библиотеки, каким его видит подбор.
class WaveLibrary {
  WaveLibrary({
    required this.lib,
    required this.disliked,
    PlayStats? stats,
    this.recent = const [],
    Iterable<Track> extras = const [],
    Random? random,
  }) : stats = stats ?? PlayStats.empty,
       _extras = {for (final t in extras) t.id: t},
       _rnd = random ?? Random();

  final LibraryState lib;

  /// Сколько раз и когда слушали — журнал прослушиваний целиком, а не 200
  /// последних треков, как было до 3.0.
  final PlayStats stats;

  /// id из «Истории», свежие сверху.
  final List<String> recent;

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

  /// Сколько раз трек слушали — из журнала, см. заметку в шапке файла.
  int playCount(String trackId) => stats.playCount(trackId);

  /// Слушали ли трек за последние [days] дней.
  bool recentlyPlayed(String trackId, int days) =>
      stats.recentlyPlayed(trackId, days);

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
/// и ещё один из них же.
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

  // 3) Ещё один: следующий из топа, а если его нет или он уже взят — следующий
  // лайк. Раньше здесь был случайный трек «любимого жанра», но жанр на
  // SoundCloud — свободный текст загрузчика вперемешку с тегами («rap»,
  // «Hip-hop & Rap», «type beat»), и такой сид был по сути случайным треком
  // библиотеки; десктоп 3.0 убрал его по той же причине.
  final nextTop = byPlays.isEmpty
      ? null
      : byPlays[(rotation * 2 + 2) % byPlays.length];
  final nextFav = favs.isEmpty ? null : favs[(rotation * 2 + 2) % favs.length];
  for (final t in [nextTop, nextFav]) {
    if (t != null && seeds.add(t.id)) break;
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
  for (final id in view.recent) {
    if (view.disliked.contains(id)) continue;
    push(id);
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

/// Список, прокрученный на [by] позиций.
List<T> _rotate<T>(List<T> items, int by) {
  if (items.length < 2) return items;
  final k = by % items.length;
  return [...items.skip(k), ...items.take(k)];
}
