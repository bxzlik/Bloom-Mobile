/// Витрина «Похожие на X» на главной: один сид из топа прослушиваний и то, что
/// на него похоже, — треки и артисты вперемешку. Порт десктопного
/// `features/library/lib/similarTo.ts` (3.1).
///
/// Сид живёт сутки, как «Для вас», и чередует тип: чётный день — артист,
/// нечётный — трек. Внутри типа сиды идут по кругу по верху топа, так что
/// витрина успевает показать несколько разных «якорей».
///
/// Откуда что берётся:
///   трек-сид   → похожие треки: похожие на него самого;
///                похожие артисты: артист этого трека → его страница.
///   артист-сид → похожие артисты: его страница;
///                похожие треки: похожие на его самые слушаемые треки, но без
///                его собственных (иначе витрина стала бы его дискографией).
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/providers/artist_lookup.dart';
import '../../core/providers/music_provider.dart';
import '../../shared/util/artists.dart';
import '../../shared/util/taste.dart' show artistKey;
import 'daily_showcase.dart';
import 'for_you.dart';

/// Из скольких верхних позиций топа крутится сид.
const int _seedPool = 5;

/// Сколько сидов пробуем подряд, если первый не дал похожих.
const int _seedTries = 2;
const int _tracksMax = 14;
const int _artistsMax = 6;

/// Меньше карточек — витрина выглядит обрывком, пробуем другой сид или тип.
const int _minItems = 4;

sealed class SimilarSeed {
  const SimilarSeed();

  String get name;
  String? get cover;

  Map<String, dynamic> toJson();

  static SimilarSeed? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['kind'] == 'artist') {
      final artist = Artist.fromJson(json['artist']);
      return artist == null ? null : SimilarArtistSeed(artist);
    }
    final id = json['id'];
    if (id is! String) return null;
    return SimilarTrackSeed(
      id: id,
      name: json['name'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      cover: json['cover'] as String?,
      track: Track.fromJson(json['track']),
    );
  }
}

final class SimilarTrackSeed extends SimilarSeed {
  const SimilarTrackSeed({
    required this.id,
    required this.name,
    required this.artist,
    this.cover,
    this.track,
  });

  final String id;
  @override
  final String name;
  final String artist;
  @override
  final String? cover;

  /// Сам трек — плитка сида играет его. `null` — поднять нечем (свой файл,
  /// которого нет в библиотеке), и плитка тогда не нажимается.
  final Track? track;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'track',
    'id': id,
    'name': name,
    'artist': artist,
    if (cover != null) 'cover': cover,
    if (track != null) 'track': track!.toJson(),
  };
}

final class SimilarArtistSeed extends SimilarSeed {
  const SimilarArtistSeed(this.artist);

  final Artist artist;

  @override
  String get name => artist.name;
  @override
  String? get cover => artist.avatar;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'artist',
    'artist': artist.toJson(),
  };
}

sealed class SimilarItem {
  const SimilarItem();

  Map<String, dynamic> toJson();

  static SimilarItem? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['kind'] == 'artist') {
      final artist = Artist.fromJson(json['artist']);
      return artist == null ? null : SimilarArtistItem(artist);
    }
    final track = Track.fromJson(json['track']);
    return track == null ? null : SimilarTrackItem(track);
  }
}

final class SimilarTrackItem extends SimilarItem {
  const SimilarTrackItem(this.track);
  final Track track;

  @override
  Map<String, dynamic> toJson() => {'kind': 'track', 'track': track.toJson()};
}

final class SimilarArtistItem extends SimilarItem {
  const SimilarArtistItem(this.artist);
  final Artist artist;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'artist',
    'artist': artist.toJson(),
  };
}

class SimilarTo {
  const SimilarTo(this.seed, this.items);

  final SimilarSeed seed;
  final List<SimilarItem> items;
}

/// Номер локального дня: от него чётность типа сида и позиция в круге.
int recsDayNumber(DateTime now) =>
    DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

bool _isRealArtist(String name) {
  final n = name.trim().toLowerCase();
  return n.isNotEmpty && n != '—' && n != 'unknown artist';
}

/// Имя, артист и обложка трека: библиотека, иначе снимок из базы.
({String name, String artist, String? cover})? _metaOf(
  RecsInput input,
  String id,
) {
  final t = input.lib.tracks[id] ?? input.stats.tracks[id];
  if (t == null || t.name.isEmpty) return null;
  return (name: t.name, artist: t.artist, cover: t.cover);
}

MusicProvider? _providerOf(RecsInput input, MusicSource source) {
  final p = input.registry.byId(source.id);
  return p != null && p.isEnabled ? p : null;
}

/// Артист на площадке трека [viaTrackId]. Если трек в библиотеке и артист у
/// него один, берём точный id из самого трека: поиск по имени на SoundCloud
/// легко промахивается мимо нужного аккаунта.
Future<Artist?> _resolveArtist(
  RecsInput input,
  String name,
  String viaTrackId,
) async {
  final source = MusicSource.fromId(viaTrackId);
  final t = input.lib.tracks[viaTrackId];
  if (t != null && t.artistId != null && parseArtists(t.artist).length == 1) {
    return Artist(
      id: t.artistId!,
      name: name,
      avatar: t.artistAvatar,
      source: source,
    );
  }
  final provider = _providerOf(input, source);
  if (provider == null) return null;
  try {
    return await findArtistCached(provider, name);
  } on Object {
    return null;
  }
}

Future<ArtistPageData?> _artistPage(RecsInput input, Artist artist) async {
  final provider = _providerOf(input, artist.source);
  if (provider == null) return null;
  try {
    return await provider.getArtist(artist.id);
  } on Object {
    return null;
  }
}

/// Отбор треков: только незнакомое (не сохранённое, не слышанное, не из
/// соседней «Для вас»), без реаплоадов и не больше двух от одного артиста.
/// [excludeArtist] — ключ артиста-сида: его треки в «похожих на него» лишние.
List<Track> _pickTracks(
  RecsInput input,
  List<Track> batch,
  Set<String> skip,
  String? excludeArtist,
  List<Track> forYou,
) {
  final known = {...input.known, for (final t in forYou) t.id, ...skip};
  // Перезаливы сверяем и с соседней «Для вас»: под другим id та же песня
  // стояла бы в двух витринах одна под другой.
  final dup = input.knownDups();
  for (final t in forYou) {
    dup.add(t);
  }
  final out = <Track>[];
  final perArtist = <String, int>{};
  for (final t in batch) {
    if (out.length >= _tracksMax) break;
    if (known.contains(t.id) || input.disliked.contains(t.id)) continue;
    if (excludeArtist != null &&
        parseArtists(
          t.artist,
        ).any((n) => artistKey(n) == excludeArtist)) {
      continue;
    }
    final artist = artistKey(t.artist);
    final n = perArtist[artist] ?? 0;
    if (n >= kRecsPerArtistMax) continue;
    if (!dup.accept(t)) continue;
    perArtist[artist] = n + 1;
    known.add(t.id);
    out.add(t);
  }
  return out;
}

/// Похожие артисты без сида и повторов. Серый круг-заглушка в ряду выглядит
/// поломкой, поэтому безликих берём, только когда иначе артистов почти нет.
List<Artist> _pickArtists(List<Artist> list, String excludeKey) {
  final seen = <String>{excludeKey};
  final uniq = [
    for (final a in list)
      if (a.name.isNotEmpty && seen.add(artistKey(a.name))) a,
  ];
  final withAvatar = [
    for (final a in uniq)
      if (a.avatar != null) a,
  ];
  return (withAvatar.length >= _minItems ? withAvatar : uniq)
      .take(_artistsMax)
      .toList();
}

/// Смешать: артист на каждой третьей позиции (Т А Т Т А Т Т …) — ряд читается
/// как смесь, а не как два блока подряд. Кончился один вид — хвост добивается
/// другим.
List<SimilarItem> mixSimilar(List<Track> tracks, List<Artist> artists) {
  final out = <SimilarItem>[];
  var ti = 0;
  var ai = 0;
  while (ti < tracks.length || ai < artists.length) {
    final wantArtist = out.length % 3 == 1;
    if ((wantArtist && ai < artists.length) || ti >= tracks.length) {
      out.add(SimilarArtistItem(artists[ai++]));
    } else {
      out.add(SimilarTrackItem(tracks[ti++]));
    }
  }
  return out;
}

/// Трек-сид: самые слушаемые треки, по кругу.
Future<SimilarTo?> _fromTrack(
  RecsInput input,
  int turn,
  List<Track> forYou,
) async {
  final pool = topWithSimilar(
    input,
    limit: _seedPool * 4,
    minPlays: 2,
  ).take(_seedPool).toList();
  for (var k = 0; k < math.min(_seedTries, pool.length); k++) {
    final id = pool[(turn + k) % pool.length].id;
    final meta = _metaOf(input, id);
    if (meta == null) continue;

    final tracks = _pickTracks(
      input,
      await similarTracksFor(input.registry, id),
      {id},
      null,
      forYou,
    );
    final names = parseArtists(meta.artist);
    final first = names.isEmpty ? '' : names.first;
    final artist = _isRealArtist(first)
        ? await _resolveArtist(input, first, id)
        : null;
    final artists = artist == null
        ? const <Artist>[]
        : _pickArtists(
            (await _artistPage(input, artist))?.similarArtists ?? const [],
            artistKey(first),
          );
    final items = mixSimilar(tracks, artists);
    if (items.length < _minItems) continue;

    final track = input.lib.tracks[id] ?? input.stats.tracks[id];
    return SimilarTo(
      SimilarTrackSeed(
        id: id,
        name: meta.name,
        artist: meta.artist,
        cover: meta.cover ?? track?.cover,
        track: track,
      ),
      items,
    );
  }
  return null;
}

class _ArtistCand {
  _ArtistCand(this.name, this.key, this.cover);

  final String name;
  final String key;
  final String? cover;
  int plays = 0;

  /// Его треки из топа, самый слушаемый первым.
  final List<String> ids = [];
}

/// Топ артистов — свёртка топа треков, как в статистике профиля: совместный
/// трек идёт каждому, иначе в топе стояло бы склеенное имя, по которому
/// площадка никого не найдёт.
List<_ArtistCand> _topArtists(RecsInput input) {
  final map = <String, _ArtistCand>{};
  for (final r in topWithSimilar(input, limit: 1000)) {
    final m = _metaOf(input, r.id);
    if (m == null) continue;
    for (final name in parseArtists(m.artist)) {
      if (!_isRealArtist(name)) continue;
      final key = artistKey(name);
      final cand = map.putIfAbsent(key, () => _ArtistCand(name, key, m.cover));
      cand.plays += r.plays;
      cand.ids.add(r.id);
    }
  }
  final list = map.values.toList()..sort((a, b) => b.plays.compareTo(a.plays));
  return list.take(_seedPool).toList();
}

/// Артист-сид: самые слушаемые артисты, по кругу.
Future<SimilarTo?> _fromArtist(
  RecsInput input,
  int turn,
  List<Track> forYou,
) async {
  final pool = _topArtists(input);
  for (var k = 0; k < math.min(_seedTries, pool.length); k++) {
    final cand = pool[(turn + k) % pool.length];
    final artist = await _resolveArtist(input, cand.name, cand.ids.first);
    if (artist == null) continue;

    final page = await _artistPage(input, artist);
    final artists = _pickArtists(page?.similarArtists ?? const [], cand.key);
    // Похожие на один трек после отсева его же треков бывают жидкими — тогда
    // добираем от второго по прослушиваниям.
    final batch = <Track>[];
    var tracks = <Track>[];
    for (final id in cand.ids.take(2)) {
      batch.addAll(await similarTracksFor(input.registry, id));
      tracks = _pickTracks(input, batch, cand.ids.toSet(), cand.key, forYou);
      if (tracks.length >= _tracksMax) break;
    }
    final items = mixSimilar(tracks, artists);
    if (items.length < _minItems) continue;

    final found = page?.artist ?? artist;
    return SimilarTo(
      SimilarArtistSeed(
        Artist(
          id: found.id,
          name: found.name.isEmpty ? cand.name : found.name,
          avatar: found.avatar ?? artist.avatar ?? cand.cover,
          source: found.source,
        ),
      ),
      items,
    );
  }
  return null;
}

/// Собрать витрину. Тип сида — по чётности дня; не вышло — пробуем другой тип,
/// чтобы витрина не пропадала через день. [forYou] — соседняя витрина: её
/// треки и их перезаливы сюда не повторяются.
Future<SimilarTo?> buildSimilarTo(
  RecsInput input, {
  List<Track> forYou = const [],
}) async {
  final day = recsDayNumber(input.now);
  final turn = day ~/ 2;
  final artistFirst = day.isEven;
  for (final artist in [artistFirst, !artistFirst]) {
    final res = artist
        ? await _fromArtist(input, turn, forYou)
        : await _fromTrack(input, turn, forYou);
    if (res != null) return res;
  }
  return null;
}

final similarToProvider = NotifierProvider<SimilarToController, SimilarTo?>(
  SimilarToController.new,
);

class SimilarToController extends DailyShowcase<SimilarTo> {
  @override
  String get storeKey => 'similarTo';

  /// 2 — перезаливы сверяются со слышанным и с треками «Для вас».
  @override
  int get version => 2;

  @override
  Future<SimilarTo?> fetch() async {
    // Утром обе витрины собираются разом — ждём соседнюю, иначе сверяться
    // было бы не с чем.
    await ref.read(forYouProvider.notifier).settled();
    return buildSimilarTo(
      recsInputOf(ref),
      forYou: ref.read(forYouProvider) ?? const [],
    );
  }

  @override
  Object? encode(SimilarTo value) => {
    'seed': value.seed.toJson(),
    'items': [for (final it in value.items) it.toJson()],
  };

  @override
  SimilarTo? decode(Object? raw) {
    if (raw is! Map) return null;
    final seed = SimilarSeed.fromJson(raw['seed']);
    final items = [
      for (final it in (raw['items'] as List?) ?? const [])
        ?SimilarItem.fromJson(it),
    ];
    return seed == null || items.isEmpty ? null : SimilarTo(seed, items);
  }
}
