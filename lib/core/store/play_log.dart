/// Журнал прослушиваний — единственное честное хранилище «что и когда
/// слушали». Порт десктопного `db/playLog.ts`.
///
/// Писался под «Итоги», но с 3.0 на нём стоит всё, что считает прослушивания:
/// список «История», статистика профиля, сиды волны (читают через
/// `play_stats.dart`). Прежняя история держала ОДНУ запись на трек с лимитом
/// 200, а `StatsState` знает только «сколько треков за день» — из них не
/// получить ни «топ за неделю», ни честное «сколько раз». Поэтому здесь копится
/// сырой поток событий «трек X сыгран в момент T», и лежит он в `core/store`,
/// а не в фиче «Итогов».
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

import '../entities/entities.dart';
import 'json_store.dart';

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

  factory PlayMeta.of(Track track) => PlayMeta(
    name: track.name,
    artist: track.artist,
    cover: track.cover,
    seconds: track.duration.inSeconds,
  );

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
    final meta = {...state.meta, track.id: PlayMeta.of(track)};
    state = _trim(PlayLog(events: events, meta: meta));
    _save();
  }

  /// Добавить снимки треков, у которых их ещё нет — без событий. Нужен
  /// переходу со старой истории (`adoptLegacySnapshots`): у треков, игранных до
  /// журнала, снимка нет, а показывать строку чем-то надо. Уже лежащие снимки
  /// не трогаем — они записаны в момент прослушивания.
  ///
  /// Такой снимок без событий переживёт всё, кроме переполнения журнала:
  /// [_trim] считает его осиротевшим. При 60 тысячах событий это годы.
  void adoptMeta(Map<String, PlayMeta> snapshots) {
    final fresh = {
      for (final e in snapshots.entries)
        if (!state.meta.containsKey(e.key)) e.key: e.value,
    };
    if (fresh.isEmpty) return;
    state = PlayLog(events: state.events, meta: {...state.meta, ...fresh});
    _save();
  }

  /// Смена площадки трека: его прослушивания переезжают на новый id. Трек тот
  /// же — иначе «сменить площадку» обнулило бы ему счётчик, выкинуло бы из
  /// «Истории» и расщепило бы в «Итогах» на два.
  void renameTrack(String oldId, String newId) {
    if (oldId == newId) return;
    if (!state.events.any((e) => e.id == oldId)) return;
    final meta = {...state.meta};
    final snap = meta.remove(oldId);
    if (snap != null) meta.putIfAbsent(newId, () => snap);
    state = PlayLog(
      events: [
        for (final e in state.events)
          e.id == oldId ? PlayEvent(e.ts, newId) : e,
      ],
      meta: meta,
    );
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
