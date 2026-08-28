/// Авто-обновление плейлистов — порт десктопных `plAutoStore` + `plAutoRefresh`.
///
/// Отмеченные плейлисты обходятся по очереди и получают новые треки из своих
/// источников (`pl.sources` — как на ПК, их может быть несколько и с разных
/// площадок), так что кандидат — любой плейлист с привязками.
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
import '../../core/store/library_store.dart';
import '../../core/l10n/l10n.dart';
import '../../shared/ui/bloom_toast.dart';
import 'refresh_playlist.dart';

/// Варианты периода (минуты) — те же, что в сегмент-переключателе на ПК.
const List<int> kPlAutoIntervals = [30, 60, 180, 720, 1440];

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
    this.ids = const [],
    this.lastRun = 0,
    this.runs = const {},
    this.busy,
  });

  final bool enabled;
  final int everyMin;
  final bool onStart;

  /// Плейлисты, отмеченные пользователем: они участвуют и в расписании, и в
  /// кнопке «Обновить сейчас».
  final List<String> ids;

  /// Когда закончился последний проход — от него считается следующий.
  final int lastRun;

  final Map<String, PlAutoRun> runs;

  /// Идёт проход: `null` — простой, иначе id обновляемого плейлиста (пустая
  /// строка — проход только что стартовал).
  final String? busy;

  bool get running => busy != null;

  PlAutoState copyWith({
    bool? enabled,
    int? everyMin,
    bool? onStart,
    List<String>? ids,
    int? lastRun,
    Map<String, PlAutoRun>? runs,
    String? busy,
    bool clearBusy = false,
  }) => PlAutoState(
    enabled: enabled ?? this.enabled,
    everyMin: everyMin ?? this.everyMin,
    onStart: onStart ?? this.onStart,
    ids: ids ?? this.ids,
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

  @override
  PlAutoState build() {
    final raw = ref.read(jsonStoreProvider).readMap('plAuto');
    final everyMin = (raw['everyMin'] as num?)?.toInt();
    final runs = <String, PlAutoRun>{};
    final rawRuns = raw['runs'];
    if (rawRuns is Map) {
      rawRuns.forEach((id, value) {
        final run = PlAutoRun.fromJson(value);
        if (id is String && run != null) runs[id] = run;
      });
    }
    return PlAutoState(
      enabled: raw['enabled'] == true,
      everyMin: everyMin != null && everyMin >= 5 ? everyMin : 180,
      onStart: raw['onStart'] != false,
      ids: (raw['ids'] as List?)?.whereType<String>().toList() ?? const [],
      lastRun: (raw['lastRun'] as num?)?.toInt() ?? 0,
      runs: runs,
    );
  }

  void _save() => ref.read(jsonStoreProvider).write('plAuto', {
    'enabled': state.enabled,
    'everyMin': state.everyMin,
    'onStart': state.onStart,
    'ids': state.ids,
    'lastRun': state.lastRun,
    'runs': {for (final e in state.runs.entries) e.key: e.value.toJson()},
  });

  // ── Настройки ───────────────────────────────────────────────────────────

  /// Включение сдвигает отсчёт: иначе давно не обновлявшаяся библиотека
  /// ушла бы в проход прямо в момент нажатия тумблера.
  void setEnabled(bool value) {
    state = state.copyWith(
      enabled: value,
      lastRun: value ? DateTime.now().millisecondsSinceEpoch : state.lastRun,
    );
    _save();
  }

  void setEveryMin(int min) {
    state = state.copyWith(everyMin: min);
    _save();
  }

  void setOnStart(bool value) {
    state = state.copyWith(onStart: value);
    _save();
  }

  void toggleId(String id) {
    final ids = [...state.ids];
    if (!ids.remove(id)) ids.add(id);
    state = state.copyWith(ids: ids);
    _save();
  }

  void setIds(List<String> ids) {
    state = state.copyWith(ids: [...ids]);
    _save();
  }

  // ── Цели ────────────────────────────────────────────────────────────────

  /// Плейлисты, которым есть откуда тянуть треки.
  List<UserPlaylist> candidates() => ref
      .read(libraryProvider)
      .playlists
      .where((p) => p.sources.isNotEmpty)
      .toList();

  /// Отмеченные цели, пересечённые с реально существующими.
  List<UserPlaylist> targets() =>
      candidates().where((p) => state.ids.contains(p.id)).toList();

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
        final at = DateTime.now().millisecondsSinceEpoch;
        if (got == null) {
          failed++;
          state = state.copyWith(
            runs: {
              ...state.runs,
              pl.id: PlAutoRun(at: at, failed: true),
            },
          );
          continue;
        }
        added += got;
        if (got > 0) changed++;
        state = state.copyWith(
          runs: {
            ...state.runs,
            pl.id: PlAutoRun(at: at, added: got),
          },
        );
      }
    } finally {
      state = state.copyWith(
        clearBusy: true,
        lastRun: DateTime.now().millisecondsSinceEpoch,
      );
      _save();
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
