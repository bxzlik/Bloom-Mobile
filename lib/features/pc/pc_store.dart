/// Синхронизация с ПК — «Настройки → Компьютер».
///
/// Телефон сопрягается с Bloom на ПК (QR или код с экрана «Подключить
/// телефон») и дальше сам ходит к нему: при запуске, при возвращении в
/// приложение и уходе из него, раз в пару минут, пока приложение открыто, и по
/// кнопке. ПК не в сети — круг тихо пропускается. Сам круг — [syncWithPc].
///
/// Пока приложение на экране и ПК отвечает, телефон держит его поток событий:
/// ПК говорит «sync», когда у него появилось новое, — круг идёт сразу; своя
/// правка уходит через пару секунд после того, как записи улеглись.
///
/// Связка с ПК лежит в kv `sync.pc` (ключ телефона — только здесь, ПК держит
/// его хеш), время последнего удачного круга — `sync.at`. «Сбросить всё»
/// уносит обе вместе с базой.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteUpdate;

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
import 'pc_remote.dart';

const String _kLink = 'sync.pc';
const String _kAt = 'sync.at';

/// Как часто ходить к ПК, пока приложение на экране.
const Duration _kEvery = Duration(minutes: 2);

/// Своя правка уходит на ПК, когда записи в базу столько молчат.
const Duration _kEditSettle = Duration(seconds: 2);

/// Поток событий ПК оборвался — через сколько пробовать снова.
const Duration _kRetry = Duration(seconds: 15);

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
  const PcState({
    this.link,
    this.status = PcStatus.idle,
    this.lastSync = 0,
    this.live = false,
  });

  final PcLink? link;
  final PcStatus status;

  /// Поток событий ПК открыт: ПК на связи прямо сейчас (Connect).
  final bool live;

  /// Последний удачный круг, мс; 0 — не было.
  final int lastSync;

  bool get paired => link != null;

  PcState copyWith({
    PcLink? link,
    bool unlink = false,
    PcStatus? status,
    int? lastSync,
    bool? live,
  }) => PcState(
    link: unlink ? null : (link ?? this.link),
    status: status ?? this.status,
    lastSync: lastSync ?? this.lastSync,
    live: live ?? this.live,
  );
}

final pcProvider = NotifierProvider<PcController, PcState>(PcController.new);

class PcController extends Notifier<PcState> {
  BloomDb get _db => ref.read(dbProvider);
  Timer? _timer;
  AppLifecycleListener? _life;

  /// Поток событий ПК; `null` — не держим (ПК не отвечал, приложение скрыто).
  StreamSubscription<PcEvent>? _live;
  StreamSubscription<SqliteUpdate>? _writes;
  Timer? _settle, _retry;
  bool _shown = true;

  /// Круг попросили, пока шёл другой, — пройти ещё раз следом.
  bool _again = false;

  /// Докуда ПК принял наше после последнего круга.
  ({int seq, int play})? _pushed;

  @override
  PcState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _life?.dispose();
      _writes?.cancel();
      _settle?.cancel();
      _retry?.cancel();
      _live?.cancel();
    });
    return PcState(
      link: PcLink.fromJson(_db.get(_kLink)),
      lastSync: (_db.get(_kAt, 0) as num?)?.toInt() ?? 0,
    );
  }

  /// Расписание — из `main()`, на всё время процесса.
  void start() {
    _timer ??= Timer.periodic(_kEvery, (_) => sync());
    _life ??= AppLifecycleListener(
      onResume: () {
        _shown = true;
        sync();
      },
      // Ушёл из приложения — отдаём сделанное сразу: Android может убить
      // процесс в фоне, и до следующего запуска ПК бы его не увидел. Поток
      // событий в фоне не держим.
      onHide: () {
        _shown = false;
        _closeLive();
        sync();
      },
    );
    _writes ??= _db.updates.listen(_onWrite);
    unawaited(Future<void>.delayed(const Duration(seconds: 3), sync));
  }

  /// Один круг. Без связки или когда ПК уже отказал в доступе — ничего; во
  /// время другого круга — ещё один следом за ним.
  Future<void> sync({bool force = false}) async {
    final link = state.link;
    if (link == null) return;
    if (state.status == PcStatus.syncing) {
      _again = true;
      return;
    }
    if (state.status == PcStatus.repair && !force) return;
    _retry?.cancel();
    final dir = coversDirPath();
    if (dir == null) return;
    state = state.copyWith(status: PcStatus.syncing);
    final clearedBefore = _db.get('stats.cleared');
    try {
      final round = await syncWithPc(link, _db, dir);
      final now = BloomDb.now();
      _db.set(_kLink, round.link.toJson());
      _db.set(_kAt, now);
      state = state.copyWith(
        link: round.link,
        status: PcStatus.ok,
        lastSync: now,
      );
      _pushed = round.pushed;
      _reread(round.touched, '${_db.get('stats.cleared')}' != '$clearedBefore');
      _openLive(round.link);
      if (_again) {
        _again = false;
        unawaited(sync());
      }
      return;
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
      state = state.copyWith(
        status: e.status == 401 ? PcStatus.repair : PcStatus.failed,
      );
    } catch (e, st) {
      logError('sync', 'круг с ПК сломался: $e', st);
      state = state.copyWith(status: PcStatus.failed);
    }
    // Не дошли — то, что просили следом, сделает следующий круг по расписанию.
    _again = false;
  }

  void _openLive(PcLink link) {
    if (_live != null || !_shown) return;
    final client = PcClient(
      link.addresses.first,
      link.port,
      print: link.print,
      token: link.token,
    );
    _live = client.events().listen(
      _onEvent,
      onError: (Object e) => _liveLost('$e'),
      onDone: () => _liveLost('closed'),
      cancelOnError: true,
    );
    ref.read(pcRemoteProvider.notifier).attach(client);
    state = state.copyWith(live: true);
  }

  void _closeLive() {
    _retry?.cancel();
    _live?.cancel();
    _live = null;
    ref.read(pcRemoteProvider.notifier).detach();
    if (state.live) state = state.copyWith(live: false);
  }

  /// Связь оборвалась: ПК закрыли, сеть пропала, телефон отключили там.
  /// Пока приложение на экране — круг через [_kRetry]: он и скажет, что
  /// случилось, и, если ПК на месте, снова откроет поток.
  void _liveLost(String why) {
    _live = null;
    ref.read(pcRemoteProvider.notifier).detach();
    state = state.copyWith(live: false);
    logInfo('sync', 'поток событий ПК оборвался: $why');
    if (!_shown || !state.paired) return;
    _retry?.cancel();
    _retry = Timer(_kRetry, sync);
  }

  void _onEvent(PcEvent e) {
    final link = state.link;
    if (e.name != 'sync') {
      ref.read(pcRemoteProvider.notifier).onEvent(e);
      return;
    }
    if (link == null) return;
    final got = SyncLog(_db).got(link.device);
    final seq = e.data['seq'], play = e.data['play'];
    if ((seq is num && seq > got.seq) || (play is num && play > got.play)) {
      sync();
    }
  }

  /// Запись в базу: своя правка или прослушивание уйдут, когда записи
  /// улягутся. Без потока событий ПК, скорее всего, недоступен — ждём
  /// расписания, а не ищем его на каждую правку.
  void _onWrite(SqliteUpdate u) {
    if (_live == null) return;
    if (u.tableName != 'changes' && u.tableName != 'plays') return;
    _settle?.cancel();
    _settle = Timer(_kEditSettle, () {
      final link = state.link, pushed = _pushed;
      if (link == null || pushed == null) return;
      // Записи круга (пришедшее с ПК) сюда тоже попадают — но они не свои.
      final own = SyncLog(_db).head(link.device, ownOnly: true);
      if (own.seq > pushed.seq || own.play > pushed.play) sync();
    });
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
  Future<List<FoundPc>> findForCode() =>
      findPcs(wait: const Duration(seconds: 2));

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
    _closeLive();
    _pushed = null;
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
      state = PcState(link: link, lastSync: state.lastSync, live: state.live);
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
    if (any(['list', 'item', 'follow', 'track', 'rekey', 'dislike']) ||
        cleared) {
      ref.read(libraryProvider.notifier).reload();
    }
    if (any(['plays', 'rekey', 'track']) || cleared) {
      ref.read(playLogProvider.notifier).reload();
    }
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
