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

import '../../core/entities/entities.dart';
import '../../core/providers/registry.dart';
import '../../core/store/play_stats.dart';
import '../../shared/util/taste.dart';
import 'daily_showcase.dart';

/// Сколько сидов опрашиваем. Каждый — сетевой запрос, поэтому немного.
const int _seedLimit = 5;

/// Сколько карточек в полосе.
const int kForYouMax = 20;

/// Больше двух треков одного артиста полоса не выдерживает — становится его
/// витриной. Считается по каждому имени трека.
const int kRecsPerArtistMax = 2;

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
