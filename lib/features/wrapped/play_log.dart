/// Журнал прослушиваний для «Итогов» — порт десктопного
/// `features/wrapped/model/playLog.ts`.
///
/// Зачем отдельное хранилище. `LibraryState.history` держит ОДНУ запись на трек
/// (`{trackId, at, count}`, `at` = последнее прослушивание), а `StatsState`
/// знает только «сколько треков за день», без id. Из них нельзя получить «топ
/// треков за прошлую неделю»: у трека нет истории по датам. Поэтому здесь
/// копится сырой поток событий «трек X сыгран в момент T».
///
/// **Свой файл, а не ключ в `bloom.json`.** На ПК это IndexedDB; у нас
/// `bloom.json` переписывается ЦЕЛИКОМ на каждую правку библиотеки, и десятки
/// тысяч событий гонялись бы через `jsonEncode` при каждом лайке. Файл тот же
/// [JsonStore] (отложенная запись, временный файл + переименование), просто
/// свой — `plays.json`.
///
/// Формат компактный, потому что событий много:
///   `{"v":1,"events":[[ts,id],…],"meta":{id:[name,artist,cover,sec]}}`
/// Площадка в снимок не пишется: она однозначно берётся из префикса id
/// ([MusicSource.fromId]) — так же, как в `stats.dart`.
///
/// Отличие от ПК по обложкам: там в журнал берут только `http(s)`, потому что у
/// локального трека обложка — data-URL на десятки килобайт. У нас своя обложка
/// это короткая ссылка `local:<имя файла>`, и класть её можно как есть.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/store/json_store.dart';

/// Потолок журнала. ~15–20к событий = год очень плотного слушания; 60к с
/// запасом покрывают несколько лет. При переполнении режем самые старые
/// события (и вместе с ними — осиротевшие снимки).
const int kMaxPlayEvents = 60000;

/// Файловое хранилище журнала. Подменяется в `main()` реальным, в тестах —
/// памятью. Своё, а не общий `jsonStoreProvider`: см. шапку файла.
final playLogStoreProvider = Provider<JsonStore>(
  (ref) => throw UnimplementedError(
    'playLogStoreProvider должен быть переопределён',
  ),
);

/// Часы журнала — ради тестов (тот же приём, что у `notifClockProvider`).
final playLogClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Одно засчитанное прослушивание.
@immutable
class PlayEvent {
  const PlayEvent(this.ts, this.id);

  /// Момент, когда прослушивание засчитано (те же 90% трека, что и история).
  final int ts;
  final String id;
}

/// Снимок трека на момент прослушивания.
///
/// Держим отдельно от событий: обложка и название нужны и через год, а сам
/// трек к тому времени может уйти из библиотеки. Дублировать имя в каждое
/// событие — лишние сотни килобайт, поэтому события хранят только id.
@immutable
class PlayMeta {
  const PlayMeta({
    required this.name,
    required this.artist,
    required this.cover,
    required this.seconds,
  });

  final String name;
  final String artist;
  final String? cover;

  /// Длительность трека, секунды (0 — неизвестна).
  final int seconds;
}

@immutable
class PlayLog {
  const PlayLog({this.events = const [], this.meta = const {}});

  /// Все события, по возрастанию `ts`.
  final List<PlayEvent> events;
  final Map<String, PlayMeta> meta;

  bool get isEmpty => events.isEmpty;
}

final playLogProvider = NotifierProvider<PlayLogController, PlayLog>(
  PlayLogController.new,
);

class PlayLogController extends Notifier<PlayLog> {
  JsonStore get _store => ref.read(playLogStoreProvider);

  @override
  PlayLog build() {
    final store = _store;
    final events = <PlayEvent>[];
    for (final raw in store.readList('events')) {
      if (raw is! List || raw.length < 2) continue;
      final ts = raw[0];
      final id = raw[1];
      if (ts is! num || id is! String || id.isEmpty) continue;
      events.add(PlayEvent(ts.toInt(), id));
    }
    // Порядок в файле уже возрастающий, но чужой или правленый руками файл
    // сломал бы весь расчёт: `buildWrapped` обрывает проход по первому
    // событию за границей периода.
    events.sort((a, b) => a.ts.compareTo(b.ts));

    final meta = <String, PlayMeta>{};
    for (final e in store.readMap('meta').entries) {
      final row = e.value;
      if (row is! List || row.length < 4) continue;
      meta[e.key] = PlayMeta(
        name: row[0] as String? ?? '',
        artist: row[1] as String? ?? '',
        cover: row[2] as String?,
        seconds: (row[3] as num?)?.toInt() ?? 0,
      );
    }
    return PlayLog(events: events, meta: meta);
  }

  void _save() {
    _store.write('v', 1);
    _store.write('events', [
      for (final e in state.events) [e.ts, e.id],
    ]);
    _store.write('meta', {
      for (final e in state.meta.entries)
        e.key: [e.value.name, e.value.artist, e.value.cover, e.value.seconds],
    });
  }

  /// Записать прослушивание. Зовётся из плеера там же, где `pushHistory` и
  /// `addPlay` — одна точка на всё приложение.
  void log(Track track) {
    if (track.id.isEmpty) return;
    final ts = ref.read(playLogClockProvider)().millisecondsSinceEpoch;
    final events = [...state.events, PlayEvent(ts, track.id)];
    final meta = {
      ...state.meta,
      track.id: PlayMeta(
        name: track.name,
        artist: track.artist,
        cover: track.cover,
        seconds: track.duration.inSeconds,
      ),
    };
    state = _trim(PlayLog(events: events, meta: meta));
    _save();
  }

  /// Срезать самые старые события и вместе с ними снимки, на которые больше
  /// никто не ссылается. Чистка снимков — наша: файл переписывается целиком, и
  /// мёртвая мета стоила бы места при каждой записи (на ПК стор `meta` в IDB
  /// живёт отдельно и не мешает).
  PlayLog _trim(PlayLog log) {
    if (log.events.length <= kMaxPlayEvents) return log;
    final events = log.events.sublist(log.events.length - kMaxPlayEvents);
    final alive = {for (final e in events) e.id};
    return PlayLog(
      events: events,
      meta: {
        for (final e in log.meta.entries)
          if (alive.contains(e.key)) e.key: e.value,
      },
    );
  }

  /// Очистить журнал — часть «Очистить статистику» в профиле.
  void clear() {
    state = const PlayLog();
    _save();
  }
}
