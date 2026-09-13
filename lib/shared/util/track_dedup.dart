/// «Это тот же трек?» — общий детектор дублей. Порт десктопного
/// `shared/lib/trackDedup.ts` (3.0).
///
/// Зачем отдельно от матчера площадок (`core/providers/match.dart`): тот
/// отвечает на вопрос «какой из кандидатов лучше подходит под исходник». Здесь
/// вопрос уже — «этот трек уже есть в списке», и спрашивают его витрины главной.
///
/// Ловим прежде всего реаплоады SoundCloud: один и тот же трек залит разными
/// пользователями, id разные, и дедуп по id их не видит. Типичный вид —
/// загрузчик утаскивает имя автора в заголовок:
///
///   «целоваться»            — lightprey
///   «lightprey - целоваться» — クリソライト
///
/// Ключевой приём: сравниваем не «название против названия», а ОБЩИЙ мешок из
/// названия и артиста. Тогда перенос имени автора между полями перестаёт что-то
/// значить, и обе записи выше дают один и тот же набор токенов.
library;

import '../../core/entities/entities.dart';

final RegExp _brackets = RegExp(r'\(.*?\)|\[.*?\]');
final RegExp _nonWord = RegExp(r'[^a-zа-я0-9]+');

/// Нормализация: нижний регистр, ё→е, без скобочных уточнений, только
/// латиница, кириллица и цифры.
String normText(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(_brackets, ' ')
    .replaceAll(_nonWord, ' ')
    .trim();

/// Шумовые слова, которые сами по себе не делают трек другим. `prod`/`feat`
/// важны особенно: у реаплоадов они разбросаны как попало.
///
/// Список намеренно короткий: «free», «out», «now» — вполне себе настоящие
/// названия треков, и вычёркивание таких слов превратило бы короткое название
/// в пустой набор токенов.
const Set<String> _noise = {
  'feat', 'ft', 'featuring', 'prod', 'by', 'the', 'a', 'an', 'and', 'и', //
  'official', 'audio', 'video', 'lyrics', 'hd', 'hq', //
  'remaster', 'remastered', 'version', 'edition', 'bonus', 'track',
};

/// Значимые токены строки (без шума и пустот).
List<String> textTokens(String s) => [
  for (final w in normText(s).split(' '))
    if (w.isNotEmpty && !_noise.contains(w)) w,
];

/// Доля меньшего множества, попавшая в большее (0..1).
double containment(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var inter = 0;
  for (final t in a) {
    if (b.contains(t)) inter++;
  }
  return inter / (a.length < b.length ? a.length : b.length);
}

/// Разобранный трек: точный ключ, мешки токенов и длительность.
class TrackFingerprint {
  TrackFingerprint({
    required String name,
    required String artist,
    this.seconds = 0,
  }) {
    final n = textTokens(name);
    core = {...n, ...textTokens(artist)};
    title = n.toSet();
    key = (core.toList()..sort()).join(' ');
    titleKey = (title.toList()..sort()).join(' ');
  }

  factory TrackFingerprint.of(Track t) => TrackFingerprint(
    name: t.name,
    artist: t.artist,
    seconds: t.duration.inSeconds,
  );

  /// Название + артист одним множеством — см. шапку файла.
  late final Set<String> core;

  /// Только название — главный признак реаплоада, см. [sameTrack].
  late final Set<String> title;

  /// Точный ключ по общему мешку — быстрый путь для полностью совпавших пар.
  late final String key;

  late final String titleKey;

  /// Длительность, секунды; 0 — неизвестна.
  final int seconds;
}

/// Насколько сходятся мешки, чтобы счесть треки одним. Реаплоад того же трека
/// даёт 1.0, два РАЗНЫХ трека одного артиста — не больше ~0.67 (общее только
/// имя артиста).
const double _coreMin = 0.85;

/// Расхождение длительности, в пределах которого это ещё «тот же трек», сек.
const int _durTolerance = 5;

/// Тот же допуск для пар с ПОЛНОСТЬЮ совпавшим названием. Шире: реаплоады
/// переживают перекодировку, вступление от загрузчика и тишину в конце.
const int _durToleranceSameTitle = 25;

/// Мешок из одного токена совпадёт с чем угодно — нечёткому пути нужно хотя бы
/// два значимых слова.
const int _coreMinTokens = 2;

/// Сколько значимых слов делают название достаточно «своим», чтобы полное
/// совпадение нельзя было списать на случай. «I love you» — можно, а
/// «Серега пират team spirit» — уже нет.
const int _titleRichTokens = 4;

/// Один ли это трек. Три пути, от самого надёжного к самому осторожному:
///
/// 1. Совпал общий мешок «название + артист» — тот же трек.
/// 2. Совпало НАЗВАНИЕ целиком — главный признак реаплоада. Длинное название
///    случайно не совпадёт; короткое сверяем ещё и по длительности.
/// 3. Названия лишь похожи — нужен и сходящийся мешок, и близкая длительность.
///
/// Длительность везде предохранитель: не знаем её — нестрогие пути закрыты.
bool sameTrack(TrackFingerprint a, TrackFingerprint b) {
  if (a.key.isNotEmpty && a.key == b.key) return true;

  final dur = a.seconds > 0 && b.seconds > 0
      ? (a.seconds - b.seconds).abs()
      : null;

  if (a.titleKey.isNotEmpty && a.titleKey == b.titleKey) {
    final shorter = a.title.length < b.title.length
        ? a.title.length
        : b.title.length;
    if (shorter >= _titleRichTokens) return true;
    return dur != null && dur <= _durToleranceSameTitle;
  }

  if (dur == null || dur > _durTolerance) return false;
  if (a.core.length < _coreMinTokens || b.core.length < _coreMinTokens) {
    return false;
  }
  return containment(a.core, b.core) >= _coreMin;
}

/// Накопитель уникальных треков: [accept] отвечает `false`, если такой трек
/// уже принимали или заранее пометили через [add].
///
/// Помеченного бывает много — вся библиотека и всё слышанное, тысячи треков, —
/// поэтому нечёткое сравнение идёт не перебором, а только по отпечаткам с
/// общим словом. Это не приближение: каждый путь [sameTrack] требует хотя бы
/// одного общего токена в мешке, остальные совпасть не могут в принципе.
class DupGuard {
  final Set<String> _keys = {};
  final Map<String, List<TrackFingerprint>> _byToken = {};

  /// Заранее пометить трек как «уже есть» (библиотека, очередь) без выдачи.
  void add(Track t) => addPrint(TrackFingerprint.of(t));

  /// То же для трека, от которого остался только снимок (журнал прослушиваний).
  void addPrint(TrackFingerprint fp) {
    if (fp.key.isEmpty) return; // пустой мешок ни с чем не совпадёт
    _keys.add(fp.key);
    for (final w in fp.core) {
      (_byToken[w] ??= []).add(fp);
    }
  }

  /// Принять трек, если он новый.
  bool accept(Track t) => acceptPrint(TrackFingerprint.of(t));

  bool acceptPrint(TrackFingerprint fp) {
    if (fp.key.isEmpty) return true; // сравнивать нечего — пропускаем
    if (_keys.contains(fp.key)) return false;
    final checked = Set<TrackFingerprint>.identity();
    for (final w in fp.core) {
      for (final p in _byToken[w] ?? const <TrackFingerprint>[]) {
        if (checked.add(p) && sameTrack(fp, p)) return false;
      }
    }
    addPrint(fp);
    return true;
  }
}
