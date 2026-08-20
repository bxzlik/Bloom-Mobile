/// Сопоставление одного и того же трека на РАЗНЫХ площадках.
///
/// Порт десктопного `features/providers/lib/match.ts` — общий матчер для
/// «Сменить площадку» (нужен лучший кандидат) и «Перенести на площадку» (нужен
/// ранжированный список: спорное уходит человеку на ручной выбор).
///
/// Счёт = 0.65 × похожесть названия + 0.35 × похожесть артиста, с поправкой на
/// длительность. Названия и артисты считаются по-разному намеренно:
/// - название сравнивается симметрично (Жаккар): лишние слова у кандидата
///   («… (Sped Up)», «… — Live») ДОЛЖНЫ штрафоваться, это чаще всего другая
///   версия;
/// - артист — по вложенности: «Artist A, Artist B» на одной площадке и
///   «Artist A» на другой — тот же трек, штрафовать не за что.
library;

import '../entities/entities.dart';

/// Нормализация: нижний регистр, без скобочных уточнений, только буквы и цифры.
String _norm(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
    .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
    .trim();

/// Шумовые слова, которые сами по себе не делают трек другим.
const Set<String> _noise = {
  'feat',
  'ft',
  'featuring',
  'prod',
  'by',
  'the',
  'a',
  'an',
  'and',
  'и',
  'official',
  'audio',
  'video',
  'lyrics',
  'hd',
  'hq',
  'remaster',
  'remastered',
  'version',
  'edition',
  'bonus',
  'track',
};

Set<String> _tokens(String s) => {
  for (final w in _norm(s).split(' '))
    if (w.isNotEmpty && !_noise.contains(w)) w,
};

/// Жаккар по множествам токенов (1 — совпали полностью, 0 — не пересеклись).
double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final inter = a.intersection(b).length;
  return inter / (a.length + b.length - inter);
}

/// Вложенность: доля меньшего множества, попавшая в большее.
double _containment(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  return a.intersection(b).length / (a.length < b.length ? a.length : b.length);
}

/// Расхождение длительности, после которого счёт почти обнуляется.
const Duration _hardDurDelta = Duration(seconds: 20);

/// Расхождение, за которое лишь слегка штрафуем (разные мастеринги, тишина в
/// конце).
const Duration _softDurDelta = Duration(seconds: 5);

/// Счёт похожести кандидата на исходный трек, 0..1.
///
/// Длительность — множитель, а не слагаемое: расхождение больше
/// [_hardDurDelta] почти всегда означает другую вещь (микс, часовая сборка,
/// «slowed»), и никакое совпадение названий этого не перевешивает. Если
/// длительность неизвестна хотя бы у одного — множитель не применяем.
double matchScore(Track cand, Track src) {
  final nameA = _tokens(src.name);
  final nameB = _tokens(cand.name);
  final artA = _tokens(src.artist);
  final artB = _tokens(cand.artist);

  // Артист может быть склеен с названием (частая беда YTM-видео:
  // «Artist - Song»). Даём второй шанс: ищем токены артиста ещё и в названии.
  final artScore = [
    _containment(artA, artB),
    artA.isEmpty ? 0.0 : _containment(artA, {...nameB, ...artB}) * 0.9,
  ].reduce((a, b) => a > b ? a : b);

  var score = 0.65 * _jaccard(nameA, nameB) + 0.35 * artScore;

  final want = src.duration;
  final got = cand.duration;
  if (want > Duration.zero && got > Duration.zero) {
    final delta = (want - got).abs();
    if (delta > _hardDurDelta) {
      score *= 0.35;
    } else if (delta > _softDurDelta) {
      score *= 0.8;
    } else {
      score = score + 0.05 > 1 ? 1 : score + 0.05;
    }
  }
  return score;
}

/// Кандидат с посчитанным счётом.
class ScoredMatch {
  const ScoredMatch(this.track, this.score);

  final Track track;
  final double score;
}

/// Отранжировать выдачу площадки относительно исходного трека: не более [limit]
/// кандидатов со счётом ≥ [min], лучший первым.
List<ScoredMatch> rankMatches(
  List<Track> cands,
  Track src, {
  int limit = 5,
  double min = 0,
}) {
  final scored = [
    for (final track in cands)
      if (matchScore(track, src) case final score when score >= min)
        ScoredMatch(track, score),
  ];
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.length > limit ? scored.sublist(0, limit) : scored;
}

/// Счёт, с которого совпадение считаем достоверным без вопросов. Порог высокий
/// намеренно: на плейлисте из сотни треков ошибка матчера не видна глазами, и
/// лучше отправить сомнительное на ручной выбор, чем молча набрать каверов.
const double kAutoMatchScore = 0.72;

/// Ниже этого кандидат вообще не показывается — это уже другой трек.
const double kMinMatchScore = 0.28;
