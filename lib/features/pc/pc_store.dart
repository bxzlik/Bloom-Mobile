/// Синхронизация с ПК — «Настройки → Компьютер».
///
/// Телефон сопрягается с Bloom на ПК (QR или код с экрана «Подключить
/// телефон») и дальше сам ходит к нему: при запуске, при возвращении в
/// приложение и уходе из него, раз в пару минут, пока приложение открыто, и по
/// кнопке. ПК не в сети — круг тихо пропускается. Сам круг — [syncWithPc].
///
/// Связка с ПК лежит в kv `sync.pc` (ключ телефона — только здесь, ПК держит
/// его хеш), время последнего удачного круга — `sync.at`. «Сбросить всё»
/// уносит обе вместе с базой.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/log/bloom_log.dart';
import '../../core/store/cover_store.dart';
import '../../core/store/days_store.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_log.dart';
import '../../core/store/text_files.dart';
import '../../core/sync/pc_client.dart';
import '../../core/sync/pc_sync.dart';
import '../../core/sync/sync_log.dart';
import '../home/for_you.dart';
import '../home/similar_to.dart';
import '../profile/achievements.dart';
import '../profile/level.dart';
import '../profile/profile_store.dart';

const String _kLink = 'sync.pc';
const String _kAt = 'sync.at';

/// Как часто ходить к ПК, пока приложение на экране.
const Duration _kEvery = Duration(minutes: 2);

enum PcStatus {
  /// Не сопряжён или круг ещё не ходил.
  idle,
  syncing,

  /// Последний круг прошёл.
  ok,

  /// ПК не нашёлся в сети.
  offline,

  /// ПК больше не пускает: отключил телефон, сброшен или это другой ПК.
  repair,

  /// Что-то сломалось посреди круга.
  failed,
}

/// Чем кончилось сопряжение.
enum PairResult { ok, notBloom, unreachable, wrong, closed, tooMany, failed }

@immutable
class PcState {
  const PcState({this.link, this.status = PcStatus.idle, this.lastSync = 0});

  final PcLink? link;
  final PcStatus status;

  /// Последний удачный круг, мс; 0 — не было.
  final int lastSync;

  bool get paired => link != null;

  PcState copyWith({PcLink? link, bool unlink = false, PcStatus? status, int? lastSync}) => PcState(
    link: unlink ? null : (link ?? this.link),
    status: status ?? this.status,
    lastSync: lastSync ?? this.lastSync,
  );
}

final pcProvider = NotifierProvider<PcController, PcState>(PcController.new);

class PcController extends Notifier<PcState> {
  BloomDb get _db => ref.read(dbProvider);
  Timer? _timer;
  AppLifecycleListener? _life;

  @override
  PcState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _life?.dispose();
    });
    return PcState(
      link: PcLink.fromJson(_db.get(_kLink)),
      lastSync: (_db.get(_kAt, 0) as num?)?.toInt() ?? 0,
    );
  }

  /// Расписание — из `main()`, на всё время процесса.
  void start() {
    _timer ??= Timer.periodic(_kEvery, (_) => sync());
    // Ушёл из приложения — отдаём сделанное сразу: Android может убить
    // процесс в фоне, и до следующего запуска ПК бы его не увидел.
    _life ??= AppLifecycleListener(onResume: sync, onHide: sync);
    unawaited(Future<void>.delayed(const Duration(seconds: 3), sync));
  }

  /// Один круг. Без связки, во время другого круга или когда ПК уже
  /// отказал в доступе — ничего.
  Future<void> sync({bool force = false}) async {
    final link = state.link;
    if (link == null || state.status == PcStatus.syncing) return;
    if (state.status == PcStatus.repair && !force) return;
    final dir = coversDirPath();
    if (dir == null) return;
    state = state.copyWith(status: PcStatus.syncing);
    final clearedBefore = _db.get('stats.cleared');
    try {
      final round = await syncWithPc(link, _db, dir);
      final now = BloomDb.now();
      _db.set(_kLink, round.link.toJson());
      _db.set(_kAt, now);
      state = state.copyWith(link: round.link, status: PcStatus.ok, lastSync: now);
      _reread(round.touched, '${_db.get('stats.cleared')}' != '$clearedBefore');
    } on PcUnreachable {
      state = state.copyWith(status: PcStatus.offline);
    } on PcPrintMismatch {
      logWarn('sync', 'сертификат ПК не тот — нужно подключить заново');
      state = state.copyWith(status: PcStatus.repair);
    } on PcChanged {
      logWarn('sync', 'по адресу ответил другой ПК — нужно подключить заново');
      state = state.copyWith(status: PcStatus.repair);
    } on PcHttpError catch (e) {
      logWarn('sync', 'ПК ответил ${e.status} ${e.code}');
      state = state.copyWith(status: e.status == 401 ? PcStatus.repair : PcStatus.failed);
    } catch (e, st) {
      logError('sync', 'круг с ПК сломался: $e', st);
      state = state.copyWith(status: PcStatus.failed);
    }
  }

  /// Сопряжение по тексту QR-кода с экрана ПК.
  Future<PairResult> pairQr(String text) async {
    final offer = PairOffer.parse(text);
    if (offer == null) return PairResult.notBloom;
    return _pair(
      () async => pairPc(
        addresses: offer.addresses,
        port: offer.port,
        print: offer.print,
        secret: offer.secret,
        name: await _name(),
        device: SyncLog(_db).device(),
      ),
    );
  }

  /// ПК с открытым окном «Подключить телефон» — для ввода кода.
  Future<List<FoundPc>> findForCode() => findPcs(wait: const Duration(seconds: 2));

  Future<PairResult> pairCode(FoundPc pc, String code) => _pair(
    () async => pairPc(
      addresses: [pc.address],
      port: pc.port,
      code: code,
      name: await _name(),
      device: SyncLog(_db).device(),
    ),
  );

  /// Забыть ПК. На ПК телефон остаётся в списке, пока его не отключат там.
  void unpair() {
    _db.set(_kLink, null);
    _db.set(_kAt, null);
    state = const PcState();
    logInfo('sync', 'ПК забыт');
  }

  Future<PairResult> _pair(Future<PcLink?> Function() run) async {
    try {
      final link = await run();
      if (link == null) return PairResult.unreachable;
      _db.set(_kLink, link.toJson());
      state = PcState(link: link, lastSync: state.lastSync);
      logInfo('sync', 'сопряжён с ПК «${link.name}»');
      unawaited(sync());
      return PairResult.ok;
    } on PcHttpError catch (e) {
      return switch (e.code) {
        'wrong' => PairResult.wrong,
        'not_pairing' => PairResult.closed,
        'too_many' => PairResult.tooMany,
        _ => PairResult.failed,
      };
    } on PcPrintMismatch {
      return PairResult.notBloom;
    } catch (e) {
      logWarn('sync', 'сопряжение не вышло: $e');
      return PairResult.failed;
    }
  }

  static Future<String> _name() async => (await deviceName()) ?? 'Phone';

  /// Что изменил круг — перечитать в памяти.
  void _reread(Set<String> touched, bool cleared) {
    bool any(List<String> kinds) => kinds.any(touched.contains);
    // Дизлайки волна перечитывает сама вслед за библиотекой.
    if (any(['list', 'item', 'follow', 'track', 'rekey', 'dislike']) || cleared) {
      ref.read(libraryProvider.notifier).reload();
    }
    if (any(['plays', 'rekey', 'track']) || cleared) ref.read(playLogProvider.notifier).reload();
    if (any(['days']) || cleared) ref.read(daysProvider.notifier).reload();
    if (any(['kv'])) {
      ref.read(profileProvider.notifier).reload();
      ref.invalidate(profileSinceProvider);
    }
    if (cleared) {
      ref.invalidate(levelBankedProvider);
      ref.invalidate(unlockedAchievementsProvider);
      ref.read(forYouProvider.notifier).reset();
      ref.read(similarToProvider.notifier).reset();
    }
  }
}
