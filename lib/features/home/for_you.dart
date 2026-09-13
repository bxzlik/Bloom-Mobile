/// Витрина «Для вас» на главной: похожие на то, что человек слушает чаще всего.
/// Порт десктопного `features/library/lib/forYou.ts` (3.0).
///
/// Сиды — из журнала прослушиваний ([PlayStats]), а не из «Истории»: самое
/// слушаемое по списку недавнего — это «самое слушаемое из недавнего».
///
/// Сид не нужно резолвить в [Track]: сквозной id уже несёт площадку (`sc_123`,
/// `ym_456`), и провайдеру его хватает. Поэтому подборка собирается и по
/// трекам, которых давно нет в библиотеке. Свои файлы отсеиваются тем же шагом —
/// у них площадки нет, похожих спросить не у кого.
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/registry.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_stats.dart';
import '../../shared/util/track_dedup.dart';
import '../wave/wave_store.dart';
import '../wave/wave_types.dart' show normalizeArtist;
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
/// витриной.
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

  /// Всё, что человек уже знает: сохранённое и когда-либо слышанное.
  late final Set<String> known = {
    ...lib.tracks.keys,
    for (final r in stats.allPlayed()) r.id,
  };

  /// Отсев перезаливов по всему знакомому. Сверки [known] мало: копия того же
  /// трека от другого загрузчика приходит под своим id. Слышанное, но не
  /// сохранённое, сверяем по снимку из журнала — название, артист, длительность.
  /// Каждый раз новый: накопитель запоминает принятое.
  DupGuard knownDups() {
    final guard = DupGuard();
    for (final t in lib.tracks.values) {
      guard.add(t);
    }
    for (final r in stats.allPlayed()) {
      if (lib.tracks.containsKey(r.id)) continue;
      final m = stats.meta[r.id];
      if (m == null) continue;
      guard.addPrint(
        TrackFingerprint(name: m.name, artist: m.artist, seconds: m.seconds),
      );
    }
    return guard;
  }
}

RecsInput recsInputOf(Ref ref) => RecsInput(
  registry: ref.read(registryProvider),
  stats: ref.read(playStatsProvider),
  lib: ref.read(libraryProvider),
  disliked: ref.read(waveStoreProvider).dislikes.keys.toSet(),
);

/// Есть ли у площадки трека похожие. YouTube Music related не отдаёт, у своих
/// файлов спросить не у кого.
bool hasSimilarSource(String id) =>
    id.startsWith('sc_') || id.startsWith('ym_');

/// Самое слушаемое с площадок, у которых есть похожие: за окно, а если данных
/// мало — за всё время.
List<TopPlayed> topWithSimilar(
  RecsInput input, {
  required int limit,
  int minPlays = 1,
}) {
  List<TopPlayed> pick({int? sinceDays, required int minPlays}) => [
    for (final r in input.stats.topPlayed(
      sinceDays: sinceDays,
      limit: limit,
      minPlays: minPlays,
      now: input.now,
    ))
      if (hasSimilarSource(r.id)) r,
  ];
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

/// Сиды: самое слушаемое за окно; добивка — свежие лайки и недавно добавленное
/// (трек могли залайкать вчера и ещё ни разу не отыграть, но как указание на
/// вкус он не хуже заслушанного).
List<String> pickForYouSeeds(RecsInput input, {int limit = _seedLimit}) {
  final out = <String>[];
  final seen = <String>{};
  void push(String id) {
    if (out.length >= limit) return;
    if (!hasSimilarSource(id) || input.disliked.contains(id)) return;
    if (seen.add(id)) out.add(id);
  }

  for (final r in topWithSimilar(input, limit: limit * 4, minPlays: 2)) {
    push(r.id);
  }
  for (final t in input.lib.favTracks) {
    push(t.id);
  }
  for (final t in input.lib.allTracks) {
    push(t.id);
  }
  return out;
}

/// Собрать полосу. Сборка идёт «по кругу» — по треку от каждого сида за проход:
/// иначе первый сид с длинным related забивает всю полосу, и подборка выглядит
/// как похожие на один трек.
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

  final out = <Track>[];
  final perArtist = <String, int>{};
  final maxLen = batches.map((b) => b.length).reduce(math.max);
  for (var i = 0; i < maxLen && out.length < kForYouMax; i++) {
    for (final batch in batches) {
      if (out.length >= kForYouMax) break;
      if (i >= batch.length) continue;
      final t = batch[i];
      if (known.contains(t.id) || input.disliked.contains(t.id)) continue;
      final artist = normalizeArtist(t.artist);
      final n = perArtist[artist] ?? 0;
      if (n >= kRecsPerArtistMax) continue;
      // Последней — самая дорогая проверка, чтобы не гонять её на отсеянных.
      if (!dup.accept(t)) continue;
      perArtist[artist] = n + 1;
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

  /// 2 — перезаливы сверяются и со слышанным, не только с библиотекой.
  @override
  int get version => 2;

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
