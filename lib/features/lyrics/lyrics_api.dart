/// Поиск текста песни в LRCLIB — порт `lyrics_service.rs` (c:\bloom\bloom),
/// часть `fetch_lrclib` вместе с нормализацией запроса и скорингом попаданий.
///
/// Чего НЕ переносили: **локальный тег файла** — на ПК текст читается из ID3
/// своей же библиотеки с диска. У нас локальных файлов нет: офлайн-копия
/// скачана у площадки и тега с текстом не несёт.
///
/// Порядок попыток тот же, что на десктопе: точный запрос с длительностью →
/// точный по «очищенному» названию → поиск строкой со скорингом → разбор
/// названия вида «Артист - Трек» и повтор по нему.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lrc.dart';

/// Найденный текст. `synced` пуст — синхронизации нет, только plain.
class LyricsResult {
  const LyricsResult({
    required this.found,
    this.plain = '',
    this.synced = '',
    this.source = 'none',
  });

  const LyricsResult.notFound() : this(found: false);

  final bool found;
  final String plain;
  final String synced;

  /// Откуда взяли: `lrclib/exact`, `lrclib/exact-clean`, `lrclib/search`.
  final String source;

  Map<String, Object?> toJson() => {
    'plain': plain,
    'synced': synced,
    'source': source,
  };

  static LyricsResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final plain = raw['plain'] is String ? raw['plain'] as String : '';
    final synced = raw['synced'] is String ? raw['synced'] as String : '';
    if (plain.trim().isEmpty && synced.trim().isEmpty) return null;
    return LyricsResult(
      found: true,
      plain: plain,
      synced: synced,
      source: raw['source'] is String ? raw['source'] as String : '',
    );
  }
}

const String _base = 'https://lrclib.net/api';
const String _ua = 'Bloom/1.0 (github.com/bloom)';
const Duration _timeout = Duration(seconds: 15);

/// Минимальный балл попадания в выдаче поиска — ниже него считаем, что нашли
/// не ту песню. Число с ПК.
const int kMinSearchScore = 20;

/// Запросить текст для «артист — название».
///
/// [durationSec] — длительность трека; с ней LRCLIB отдаёт точное совпадение
/// (у одной песни бывает десяток версий разной длины).
Future<LyricsResult> fetchLyrics({
  required String artist,
  required String title,
  int? durationSec,
  http.Client? client,
}) async {
  if (title.trim().isEmpty) return const LyricsResult.notFound();
  final http = client ?? _sharedClient;

  final direct = await _lrclib(artist, title, durationSec, http);
  if (direct.found) return direct;

  // Название вида «Артист - Трек» (обычное дело у SoundCloud и YouTube):
  // пробуем разобрать его на части и спросить ещё раз.
  final idx = title.indexOf(' - ');
  if (idx > 0) {
    final altArtist = title.substring(0, idx).trim();
    final altTitle = title.substring(idx + 3).trim();
    if (altTitle.isNotEmpty) {
      final r = await _lrclib(altArtist, altTitle, durationSec, http);
      if (r.found) return r;
    }
  }
  return const LyricsResult.notFound();
}

Future<LyricsResult> _lrclib(
  String artist,
  String title,
  int? durationSec,
  http.Client client,
) async {
  // 1. Точное совпадение с длительностью.
  if (durationSec != null && durationSec > 0 && artist.isNotEmpty) {
    final r = await _get(
      client,
      '$_base/get?artist_name=${Uri.encodeQueryComponent(artist)}'
          '&track_name=${Uri.encodeQueryComponent(title)}'
          '&duration=$durationSec',
      'lrclib/exact',
    );
    if (r.found) return r;
  }

  // 2. То же, но по очищенному от «(feat. …)», «(Official Video)» и прочего
  //    мусора названию — иначе точный запрос почти всегда мимо.
  final cleanTitle = normalizeForSearch(title);
  final cleanArtist = normalizeForSearch(artist);
  final changed =
      cleanTitle.toLowerCase() != title.toLowerCase() ||
      cleanArtist.toLowerCase() != artist.toLowerCase();
  if (durationSec != null &&
      durationSec > 0 &&
      cleanArtist.isNotEmpty &&
      changed) {
    final r = await _get(
      client,
      '$_base/get?artist_name=${Uri.encodeQueryComponent(cleanArtist)}'
          '&track_name=${Uri.encodeQueryComponent(cleanTitle)}'
          '&duration=$durationSec',
      'lrclib/exact-clean',
    );
    if (r.found) return r;
  }

  // 3. Поиск строкой: берём лучшее попадание по скорингу.
  final q = artist.isEmpty ? title : '$artist $title';
  final body = await _json(
    client,
    '$_base/search?q=${Uri.encodeQueryComponent(q)}',
  );
  if (body is! List || body.isEmpty) return const LyricsResult.notFound();

  Map<String, Object?>? best;
  var bestScore = -1;
  var bestSynced = false;
  for (final raw in body) {
    if (raw is! Map) continue;
    final item = raw.cast<String, Object?>();
    final hasSynced = (item['syncedLyrics'] as String? ?? '').isNotEmpty;
    final score = scoreHit(
      hitTitle: item['trackName'] as String? ?? '',
      hitArtist: item['artistName'] as String? ?? '',
      queryTitle: title,
      queryArtist: artist,
    );
    // Синхронный текст ценнее чуть более точного совпадения названия: ради
    // подсветки строк мы всё это и затевали. Порог форы — с ПК.
    if (score > bestScore ||
        (score >= bestScore - 10 && hasSynced && !bestSynced)) {
      best = item;
      bestScore = score;
      bestSynced = hasSynced;
    }
  }
  if (best == null || bestScore < kMinSearchScore) {
    return const LyricsResult.notFound();
  }
  return _parseItem(best, 'lrclib/search');
}

Future<LyricsResult> _get(http.Client client, String url, String source) async {
  final body = await _json(client, url);
  if (body is! Map) return const LyricsResult.notFound();
  return _parseItem(body.cast<String, Object?>(), source);
}

Future<Object?> _json(http.Client client, String url) async {
  try {
    final res = await client
        .get(Uri.parse(url), headers: const {'User-Agent': _ua})
        .timeout(_timeout);
    if (res.statusCode != 200) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  } catch (_) {
    // Нет сети, таймаут, мусор вместо JSON — текста просто нет.
    return null;
  }
}

LyricsResult _parseItem(Map<String, Object?> item, String source) {
  final plain = item['plainLyrics'] as String? ?? '';
  final synced = item['syncedLyrics'] as String? ?? '';
  if (plain.trim().isEmpty && synced.trim().isEmpty) {
    return const LyricsResult.notFound();
  }
  return LyricsResult(
    found: true,
    plain: plain.isEmpty && synced.isNotEmpty ? stripLrc(synced) : plain,
    synced: synced,
    source: source,
  );
}

final http.Client _sharedClient = http.Client();

// ---------------- Нормализация и скоринг ----------------

/// Скобочный мусор: «(feat. …)», «(Remix)», да и любые скобки вообще.
final RegExp _noise = RegExp(
  r'[\(\[](feat\.?|ft\.?|featuring)[^\)\]]*[\)\]]'
  r'|[\(\[](remix|edit|version|deluxe|remaster|live|acoustic|bonus|original\s*mix)[^\)\]]*[\)\]]'
  r'|[\(\[][^\)\]]*[\)\]]',
  caseSensitive: false,
);

/// Мусор из названий с YouTube и SoundCloud: «Official Video», «prod. by …».
final RegExp _titleJunk = RegExp(
  r'\b(?:official\s+(?:music\s+)?(?:video|audio|clip|lyric(?:s\s+)?video))'
  r'|\b(?:lyric(?:s)?\s+video|audio|visuali[sz]er)'
  r'|[\(\[]\s*prod\.?(?:\s+by)?\s+[^\)\]]*[\)\]]'
  r'|\s*\bprod\.?(?:\s+by)?\s+.+$'
  r'|\b(?:type\s+beat)'
  r'|[\(\[]\s*(?:HD|HQ|4K|lyrics?|audio|official)\s*[\)\]]',
  caseSensitive: false,
);

final RegExp _multiSpace = RegExp(r'\s{2,}');

/// Разделители в строке артистов — по ним берётся первый, «главный».
final RegExp _artistSep = RegExp(
  r'\s*[,&/]\s*|\s+(?:feat\.?|ft\.?|featuring|and|x)\s+',
  caseSensitive: false,
);

/// Очистка названия/артиста перед запросом (`normalize_for_search` с ПК).
String normalizeForSearch(String input) {
  if (input.trim().isEmpty) return '';
  return input
      .replaceAll(_noise, ' ')
      .replaceAll(_titleJunk, ' ')
      .replaceAll(_multiSpace, ' ')
      .trim();
}

/// Первый артист из строки («A, B & C» → «A»).
String primaryArtist(String artist) {
  if (artist.trim().isEmpty) return '';
  return artist.split(_artistSep).first.trim();
}

/// Насколько попадание похоже на то, что искали: 0..100.
///
/// Название даёт до 60, артист — до 40; числа и ступени с ПК (`score_hit`).
int scoreHit({
  required String hitTitle,
  required String hitArtist,
  required String queryTitle,
  required String queryArtist,
}) {
  final ht = hitTitle.trim();
  final ha = hitArtist.trim();
  final qt = queryTitle.trim();
  final qa = queryArtist.trim();
  var score = 0;

  if (_eq(ht, qt)) {
    score += 60;
  } else if (_contains(ht, qt) || _contains(qt, ht)) {
    score += 40;
  } else {
    final nht = normalizeForSearch(ht);
    final nqt = normalizeForSearch(qt);
    if (_eq(nht, nqt)) {
      score += 50;
    } else if (_contains(nht, nqt) || _contains(nqt, nht)) {
      score += 30;
    }
  }

  if (qa.isNotEmpty && ha.isNotEmpty) {
    if (_eq(ha, qa)) {
      score += 40;
    } else if (_contains(ha, qa) || _contains(qa, ha)) {
      score += 30;
    } else {
      final pha = primaryArtist(ha);
      final pqa = primaryArtist(qa);
      if (_eq(pha, pqa)) {
        score += 35;
      } else if (_contains(pha, pqa) || _contains(pqa, pha)) {
        score += 20;
      }
    }
  }
  return score;
}

bool _eq(String a, String b) => a.toLowerCase() == b.toLowerCase();

bool _contains(String hay, String needle) =>
    needle.isNotEmpty && hay.toLowerCase().contains(needle.toLowerCase());
