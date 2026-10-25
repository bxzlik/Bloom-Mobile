/// Авто-обновление плейлистов — порт `AutoRefresh` ПК.
///
/// Отмеченные плейлисты обходятся по очереди и получают новые треки из своих
/// источников (`pl.sources` — как на ПК, их может быть несколько и с разных
/// площадок), так что кандидат — любой плейлист с привязками.
///
/// Раскладка как на ПК: отметка — флажок самого плейлиста
/// ([UserPlaylist.autoRefresh]), расписание (вкл., период, «при запуске») —
/// настройки, а когда был последний проход и чем кончился у каждого плейлиста
/// — `kv` базы (`autoRefresh.last`, `autoRefresh.runs`).
///
/// Расписание живёт таймером внутри процесса: разбудить приложение, когда его
/// закрыли, нечем — фоновых задач у нас нет. Поэтому проход случается либо при
/// запуске («Проверять при запуске»), либо пока приложение открыто; `lastRun`
/// хранится на диске, и после долгого перерыва первый же тик увидит, что срок
/// вышел.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/db.dart';
import '../../core/store/json_store.dart';
import '../../core/store/library_store.dart';
import '../../core/l10n/l10n.dart';
import '../../shared/ui/bloom_toast.dart';
import 'refresh_playlist.dart';

/// Варианты периода (минуты) — те же, что в сегмент-переключателе на ПК.
const List<int> kPlAutoIntervals = [30, 60, 180, 720, 1440];

/// Ключи `kv` — те же, что у ПК.
const String _kLast = 'autoRefresh.last';
const String _kRuns = 'autoRefresh.runs';

/// Пауза перед стартовым проходом: площадкам надо успеть подняться.
const Duration _onStartDelay = Duration(seconds: 12);

/// Как часто смотрим, не пора ли обновлять.
const Duration _tick = Duration(minutes: 1);

/// Чем кончился последний проход по конкретному плейлисту.
class PlAutoRun {
  const PlAutoRun({required this.at, this.added = 0, this.failed = false});

  final int at;
  final int added;
  final bool failed;

  Map<String, dynamic> toJson() => {
    'at': at,
    'added': added,
    if (failed) 'failed': true,
  };

  static PlAutoRun? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    if (at is! num) return null;
    return PlAutoRun(
      at: at.toInt(),
      added: (json['added'] as num?)?.toInt() ?? 0,
      failed: json['failed'] == true,
    );
  }
}

class PlAutoState {
  const PlAutoState({
    this.enabled = false,
    this.everyMin = 180,
    this.onStart = true,
    this.lastRun = 0,
    this.runs = const {},
    this.busy,
  });

  final bool enabled;
  final int everyMin;
  final bool onStart;

  /// Когда закончился последний проход — от него считается следующий.
  final int lastRun;

  /// Последнее обновление каждого плейлиста — и руками тоже, как на ПК.
  final Map<String, PlAutoRun> runs;

  /// Идёт проход: `null` — простой, иначе id обновляемого плейлиста (пустая
  /// строка — проход только что стартовал).
  final String? busy;

  bool get running => busy != null;

  PlAutoState copyWith({
    bool? enabled,
    int? everyMin,
    bool? onStart,
    int? lastRun,
    Map<String, PlAutoRun>? runs,
    String? busy,
    bool clearBusy = false,
  }) => PlAutoState(
    enabled: enabled ?? this.enabled,
    everyMin: everyMin ?? this.everyMin,
    onStart: onStart ?? this.onStart,
    lastRun: lastRun ?? this.lastRun,
    runs: runs ?? this.runs,
    busy: clearBusy ? null : (busy ?? this.busy),
  );
}

/// Итог прохода — для тех, кто его запустил руками.
class PlAutoSweep {
  const PlAutoSweep({
    this.added = 0,
    this.changed = 0,
    this.failed = 0,
    this.skipped = false,
  });

  /// Всего добавлено треков.
  final int added;

  /// В скольких плейлистах что-то появилось.
  final int changed;

  final int failed;

  /// Проход не запускался: нечего обновлять или уже идёт.
  final bool skipped;
}

final plAutoProvider = NotifierProvider<PlAutoController, PlAutoState>(
  PlAutoController.new,
);

class PlAutoController extends Notifier<PlAutoState> {
  Timer? _timer;
  bool _scheduled = false;

  BloomDb get _db => ref.read(dbProvider);

  @override
  PlAutoState build() {
    final raw = ref.read(jsonStoreProvider).readMap('plAuto');
    final everyMin = (raw['everyMin'] as num?)?.toInt();
    // Плейлисты, которых больше нет, забываются.
    final alive = {for (final p in ref.read(libraryProvider).playlists) p.id};
    final saved = _db.getMap(_kRuns);
    final runs = <String, PlAutoRun>{};
    saved.forEach((id, value) {
      final run = PlAutoRun.fromJson(value);
      if (alive.contains(id) && run != null) runs[id] = run;
    });
    if (runs.length != saved.length) _saveRuns(runs);
    return PlAutoState(
      enabled: raw['enabled'] == true,
      everyMin: everyMin != null && everyMin >= 5 ? everyMin : 180,
      onStart: raw['onStart'] != false,
      lastRun: (_db.get(_kLast) as num?)?.toInt() ?? 0,
      runs: runs,
    );
  }

  void _saveSettings() => ref.read(jsonStoreProvider).write('plAuto', {
    'enabled': state.enabled,
    'everyMin': state.everyMin,
    'onStart': state.onStart,
  });

  void _saveRuns(Map<String, PlAutoRun> runs) =>
      _db.set(_kRuns, {for (final e in runs.entries) e.key: e.value.toJson()});

  void _setLastRun(int at) {
    state = state.copyWith(lastRun: at);
    _db.set(_kLast, at);
  }

  /// Запомнить, чем кончилось обновление плейлиста: [added] `null` — ни один
  /// источник не ответил. Обновление руками считается тоже, как на ПК.
  void record(String id, int? added) {
    final runs = {
      ...state.runs,
      id: PlAutoRun(
        at: DateTime.now().millisecondsSinceEpoch,
        added: added ?? 0,
        failed: added == null,
      ),
    };
    state = state.copyWith(runs: runs);
    _saveRuns(runs);
  }

  // ── Настройки ───────────────────────────────────────────────────────────

  /// Включение сдвигает отсчёт: иначе давно не обновлявшаяся библиотека
  /// ушла бы в проход прямо в момент нажатия тумблера.
  void setEnabled(bool value) {
    state = state.copyWith(enabled: value);
    if (value) _setLastRun(DateTime.now().millisecondsSinceEpoch);
    _saveSettings();
  }

  void setEveryMin(int min) {
    state = state.copyWith(everyMin: min);
    _saveSettings();
  }

  void setOnStart(bool value) {
    state = state.copyWith(onStart: value);
    _saveSettings();
  }

  // ── Цели ────────────────────────────────────────────────────────────────

  /// Плейлисты, которым есть откуда тянуть треки.
  List<UserPlaylist> candidates() => ref
      .read(libraryProvider)
      .playlists
      .where((p) => p.sources.isNotEmpty)
      .toList();

  /// Отмеченные для автообновления.
  List<UserPlaylist> targets() =>
      candidates().where((p) => p.autoRefresh).toList();

  // ── Проход ──────────────────────────────────────────────────────────────

  /// Обойти отмеченные плейлисты по очереди.
  ///
  /// [silent] — фоновый проход по расписанию: молчим, пока ничего не нашли.
  /// Запущенный руками показывает живой тост с прогрессом.
  Future<PlAutoSweep> runSweep({bool silent = false}) async {
    if (state.running) return const PlAutoSweep(skipped: true);
    final targets = this.targets();
    if (targets.isEmpty) return const PlAutoSweep(skipped: true);

    final messenger = bloomMessengerKey.currentState;
    // Проход по расписанию говорит из таймера, когда своего экрана у него нет,
    // — язык берётся у глобального мессенджера (см. `globalL10n`).
    final l10n = globalL10n;
    final toast = silent || l10n == null
        ? null
        : messenger?.busyToast(l10n.paBusy(targets.length));

    state = state.copyWith(busy: '');
    final registry = ref.read(registryProvider);
    final library = ref.read(libraryProvider.notifier);
    var added = 0;
    var changed = 0;
    var failed = 0;

    try {
      for (var i = 0; i < targets.length; i++) {
        final pl = targets[i];
        state = state.copyWith(busy: pl.id);
        toast?.update(
          l10n!.paProgress(i + 1, targets.length),
          progress: i / targets.length,
        );
        final got = await refreshPlaylistFromSource(registry, library, pl);
        record(pl.id, got);
        if (got == null) {
          failed++;
          continue;
        }
        added += got;
        if (got > 0) changed++;
      }
    } finally {
      state = state.copyWith(clearBusy: true);
      _setLastRun(DateTime.now().millisecondsSinceEpoch);
    }

    final result = PlAutoSweep(added: added, changed: changed, failed: failed);
    if (l10n == null) return result;
    if (added > 0) {
      final text = l10n.paNewTracks(added, changed);
      toast == null
          ? messenger?.toast(text, kind: ToastKind.success)
          : toast.finish(text);
    } else if (failed > 0) {
      final text = l10n.paFailed(failed);
      toast == null
          ? messenger?.toast(text, kind: ToastKind.warn)
          : toast.finish(text, kind: ToastKind.warn);
    } else {
      toast?.finish(l10n.paNoNewTracks, kind: ToastKind.info);
    }
    return result;
  }

  // ── Расписание ──────────────────────────────────────────────────────────

  /// Поднять фоновый таймер. Идемпотентно: зовётся один раз из `main`.
  void startScheduler() {
    if (_scheduled) return;
    _scheduled = true;

    if (state.enabled && state.onStart) {
      Timer(_onStartDelay, () {
        if (state.enabled) unawaited(runSweep(silent: true));
      });
    }

    _timer = Timer.periodic(_tick, (_) {
      if (!state.enabled) return;
      final due =
          DateTime.now().millisecondsSinceEpoch - state.lastRun >=
          state.everyMin * 60 * 1000;
      if (due) unawaited(runSweep(silent: true));
    });
    ref.onDispose(() => _timer?.cancel());
  }
}
