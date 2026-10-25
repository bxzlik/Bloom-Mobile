/// Витрина «Для вас» на главной: похожие на то, что человек слушает, —
/// `Home::buildForYou` ПК.
///
/// Сиды — самое слушаемое из журнала прослушиваний ([PlayStats]), потом свежие
/// лайки и свежее в библиотеке: трек, залайканный вчера и ещё не сыгранный,
/// говорит о вкусе не меньше. Сначала по одному на артиста — пять хитов одного
/// артиста сделали бы полосу его витриной.
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/registry.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_stats.dart';
import '../../shared/util/taste.dart';
import '../../shared/util/track_dedup.dart';
import '../wave/wave_store.dart';
import 'daily_showcase.dart';

/// Окно «текущего вкуса»: вкус двухлетней давности рекомендациям только мешает.
const int kRecsWindowDays = 90;

/// Меньше позиций за окно — считаем за всё время (новая установка).
const int _windowMinSeeds = 3;

/// Сколько сидов опрашиваем. Каждый — сетевой запрос, поэтому немного.
const int _seedLimit = 5;

/// Сколько карточек в полосе.
const int kForYouMax = 20;

/// Больше двух треков одного артиста полоса не выдерживает — становится его
/// витриной. Считается по каждому имени трека.
const int kRecsPerArtistMax = 2;

/// Всё, из чего собираются витрины. Снимок, а не живые сторы: сборка идёт
/// секунды, и подборка обязана быть собрана по одному состоянию.
class RecsInput {
  RecsInput({
    required this.registry,
    required this.stats,
    required this.lib,
    this.disliked = const {},
    DateTime? now,
  }) : now = now ?? DateTime.now();

  final ProviderRegistry registry;
  final PlayStats stats;
  final LibraryState lib;

  /// Дизлайки волны — в витрину они не попадают ни сидом, ни карточкой.
  final Set<String> disliked;
  final DateTime now;

  /// Трек по id: из библиотеки, иначе его снимок из журнала.
  Track? trackOf(String id) => lib.tracks[id] ?? stats.tracks[id];

  /// Всё, что человек уже знает: сохранённое и когда-либо слышанное.
  late final Set<String> known = {
    ...lib.tracks.keys,
    for (final r in stats.allPlayed()) r.id,
  };

  /// Отсев перезаливов по всему знакомому. Сверки [known] мало: копия того же
  /// трека от другого загрузчика приходит под своим id. Слышанное, но не
  /// сохранённое, сверяем по его снимку из базы. Каждый раз новый: накопитель
  /// запоминает принятое.
  DupGuard knownDups() {
    final guard = DupGuard();
    for (final t in lib.tracks.values) {
      guard.add(t);
    }
    for (final e in stats.tracks.entries) {
      if (!lib.tracks.containsKey(e.key)) guard.add(e.value);
    }
    return guard;
  }
}

RecsInput recsInputOf(Ref ref) => RecsInput(
  registry: ref.read(registryProvider),
  stats: ref.read(playStatsProvider),
  lib: ref.read(libraryProvider),
  disliked: ref.read(waveStoreProvider).dislikedIds,
);

/// Можно ли спросить похожие: площадка трека включена и у неё есть радио для
/// него — `Taste::askable` ПК. Своим файлам спросить не у кого.
bool recsAskable(RecsInput input, Track t) {
  final p = input.registry.byId(t.source.id);
  return p != null && p.isEnabled && p.trackStation(t).isNotEmpty;
}

/// Снимок трека есть, и о нём можно спросить.
bool _askableId(RecsInput input, String id) {
  final t = input.trackOf(id);
  return t != null && recsAskable(input, t);
}

/// Самое слушаемое, о чём можно спросить, без дизлайков, — `Taste::topTracks`
/// ПК: за окно, а пока там мало — за всё время.
List<TopPlayed> recsTopPlayed(
  RecsInput input, {
  required int limit,
  int minPlays = 1,
}) {
  List<TopPlayed> pick({int? sinceDays, required int minPlays}) => [
    for (final r in input.stats.topPlayed(
      sinceDays: sinceDays,
      limit: limit * 4,
      minPlays: minPlays,
      now: input.now,
    ))
      if (!input.disliked.contains(r.id) && _askableId(input, r.id)) r,
  ].take(limit).toList();
  final top = pick(sinceDays: kRecsWindowDays, minPlays: minPlays);
  return top.length >= _windowMinSeeds ? top : pick(minPlays: 1);
}

/// Похожие на трек у его площадки. Площадку решает префикс id; без метода или
/// с упавшей сетью — пусто: один сид не повод хоронить витрину.
Future<List<Track>> similarTracksFor(
  ProviderRegistry registry,
  String seedId,
) async {
  final provider = registry.byId(MusicSource.fromId(seedId).id);
  if (provider == null || !provider.isEnabled) return const [];
  try {
    return await provider.getSimilarTracks(seedId) ?? const [];
  } on Object {
    return const [];
  }
}

/// Список свежими сверху по времени добавления [at] — `Taste::newestIn` ПК.
List<Track> newestFirst(List<Track> list, Map<String, int> at) {
  final rows = [for (var i = 0; i < list.length; i++) (list[i], i)]
    ..sort((a, b) {
      final c = (at[b.$1.id] ?? 0).compareTo(at[a.$1.id] ?? 0);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
  return [for (final x in rows) x.$1];
}

/// Сиды: самое слушаемое, свежие лайки, свежее в библиотеке; первым проходом —
/// по одному на артиста, вторым — добор.
List<String> pickForYouSeeds(RecsInput input, {int limit = _seedLimit}) {
  final all = [
    for (final r in recsTopPlayed(input, limit: limit * 3, minPlays: 2))
      ?input.trackOf(r.id),
    ...newestFirst(input.lib.favTracks, input.lib.favs),
    ...newestFirst(input.lib.allTracks, input.lib.inLib),
  ];
  final out = <String>[];
  final seen = <String>{};
  final artists = <String>{};
  for (final spread in [true, false]) {
    for (final t in all) {
      if (out.length >= limit) return out;
      final keys = artistKeys(t);
      if (seen.contains(t.id) ||
          (spread && keys.any(artists.contains)) ||
          input.disliked.contains(t.id) ||
          !recsAskable(input, t)) {
        continue;
      }
      seen.add(t.id);
      artists.addAll(keys);
      out.add(t.id);
    }
  }
  return out;
}

/// Собрать полосу. По кругу — по треку от каждого сида за проход: иначе
/// длинный список первого сида забивает всю полосу.
Future<List<Track>> buildForYou(RecsInput input) async {
  final seeds = pickForYouSeeds(input);
  if (seeds.isEmpty) return const [];

  // Последовательно: у SoundCloud общая очередь запросов, веером они всё равно
  // выстроятся в неё, зато параллельный старт мешает остальной главной.
  final batches = <List<Track>>[];
  for (final seed in seeds) {
    final batch = await similarTracksFor(input.registry, seed);
    if (batch.isNotEmpty) batches.add(batch);
  }
  if (batches.isEmpty) return const [];

  final known = {...input.known, ...seeds};
  // Сверка не только по id: один трек на двух площадках имеет разные id, а на
  // SoundCloud ещё и реаплоады от разных загрузчиков.
  final dup = input.knownDups();
  final cap = ArtistCap(kRecsPerArtistMax);

  final out = <Track>[];
  final maxLen = batches.map((b) => b.length).reduce(math.max);
  for (var i = 0; i < maxLen && out.length < kForYouMax; i++) {
    for (final batch in batches) {
      if (out.length >= kForYouMax) break;
      if (i >= batch.length) continue;
      final t = batch[i];
      if (known.contains(t.id) || input.disliked.contains(t.id)) continue;
      if (!cap.fits(t)) continue;
      // Последней — самая дорогая проверка, чтобы не гонять её на отсеянных.
      if (!dup.accept(t)) continue;
      known.add(t.id);
      cap.take(t);
      out.add(t);
    }
  }
  return out;
}

final forYouProvider = NotifierProvider<ForYouController, List<Track>?>(
  ForYouController.new,
);

class ForYouController extends DailyShowcase<List<Track>> {
  @override
  String get storeKey => 'forYou';

  /// 3 — правила ПК: сиды по одному на артиста, YouTube Music тоже сид,
  /// потолок артиста по каждому имени.
  @override
  int get version => 3;

  @override
  Future<List<Track>?> fetch() async {
    final tracks = await buildForYou(recsInputOf(ref));
    return tracks.isEmpty ? null : tracks;
  }

  @override
  Object? encode(List<Track> value) => [for (final t in value) t.toJson()];

  @override
  List<Track>? decode(Object? raw) {
    if (raw is! List) return null;
    final tracks = [for (final t in raw) ?Track.fromJson(t)];
    return tracks.isEmpty ? null : tracks;
  }
}
