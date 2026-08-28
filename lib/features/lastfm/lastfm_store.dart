/// Скробблер Last.fm — порт десктопного `features/lastfm/model/lastfmStore.ts`.
///
/// Хранит ключи приложения, ключ сессии и два флага; он же и считает, когда
/// трек пора засчитывать. Правило зачёта десктопное (оно же — требование самого
/// Last.fm): прослушано не меньше [kLfmMinListen] И при этом либо
/// [kLfmAbsolute], либо половина длительности.
///
/// Про плеер стор не знает: события ему приносит `PlaybackController` вызовами
/// [LastfmController.onTrackStart] и [LastfmController.onProgress] — тот же
/// расклад, что у скорости и таймера сна. На десктопе эту роль играет
/// `useLastfmBridge`, подписанный на два стора.
///
/// Текстов здесь нет: наружу уходит типизированная причина [LfmNote], фразу
/// собирает экран настроек (как у авторизации Яндекса).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart' show jsonStoreProvider;
import 'lastfm_api.dart';

/// Порог «слушали достаточно», чтобы засчитывать вообще.
const Duration kLfmMinListen = Duration(seconds: 30);

/// Длинный трек засчитывается после этого времени, не дожидаясь половины.
const Duration kLfmAbsolute = Duration(seconds: 240);

enum LfmNoteKind {
  /// Идёт `auth.getToken`.
  gettingToken,

  /// Токен получен, браузер открыт — ждём подтверждения.
  confirmAccess,

  /// Идёт `auth.getSession`.
  checking,

  /// Доступ ещё не подтверждён — можно нажать «Готово» ещё раз.
  notConfirmed,

  /// Вход не начинали, подтверждать нечего.
  loginFirst,

  /// Нет ключей приложения — сначала их надо сохранить.
  needKeys,

  /// Сеть не ответила.
  networkError,

  /// Отказ площадки; текст лежит в [LfmNote.message].
  error,
}

class LfmNote {
  const LfmNote(this.kind, [this.message]);

  final LfmNoteKind kind;
  final String? message;
}

class LastfmState {
  const LastfmState({
    this.sk,
    this.apiKey = '',
    this.apiSecret = '',
    this.scrobbleEnabled = false,
    this.nowPlayingEnabled = false,
    this.user = '',
    this.note,
    this.oauthPending = false,
    this.busy = false,
  });

  /// Ключ сессии. Есть — значит подключено.
  final String? sk;

  /// Ключи приложения: свои у каждого, вшитых нет.
  final String apiKey;
  final String apiSecret;

  final bool scrobbleEnabled;
  final bool nowPlayingEnabled;

  /// Ник на Last.fm.
  final String user;

  /// Что показать под кнопками входа.
  final LfmNote? note;

  /// Токен получен, браузер открыт — показываем «Готово».
  final bool oauthPending;

  /// Идёт сетевой шаг входа.
  final bool busy;

  bool get connected => (sk ?? '').isNotEmpty;
  bool get hasKeys => apiKey.isNotEmpty && apiSecret.isNotEmpty;

  LastfmState copyWith({
    String? sk,
    bool clearSk = false,
    String? apiKey,
    String? apiSecret,
    bool? scrobbleEnabled,
    bool? nowPlayingEnabled,
    String? user,
    LfmNote? note,
    bool clearNote = false,
    bool? oauthPending,
    bool? busy,
  }) => LastfmState(
    sk: clearSk ? null : (sk ?? this.sk),
    apiKey: apiKey ?? this.apiKey,
    apiSecret: apiSecret ?? this.apiSecret,
    scrobbleEnabled: scrobbleEnabled ?? this.scrobbleEnabled,
    nowPlayingEnabled: nowPlayingEnabled ?? this.nowPlayingEnabled,
    user: user ?? this.user,
    note: clearNote ? null : (note ?? this.note),
    oauthPending: oauthPending ?? this.oauthPending,
    busy: busy ?? this.busy,
  );
}

final lastfmProvider = NotifierProvider<LastfmController, LastfmState>(
  LastfmController.new,
);

/// Часы скробблера — вынесены ради тестов (тот же приём, что
/// `sleepClockProvider`).
final lfmClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

class LastfmController extends Notifier<LastfmState> {
  static const _key = 'lastfm';

  /// Разовый токен между `auth.getToken` и `auth.getSession`. На диск не идёт:
  /// он живёт минуты и годен один раз.
  String? _pendingToken;

  /// Что играет сейчас, когда началось и засчитали ли. Транзиентное состояние —
  /// в состоянии провайдера ему делать нечего (меняется на каждом тике, а в
  /// интерфейсе не показывается) — ровно как модульные переменные на ПК.
  ({String artist, String track, String album})? _nowTrack;
  int _startedAt = 0;
  bool _scrobbled = false;

  @override
  LastfmState build() {
    final raw = ref.read(jsonStoreProvider).readMap(_key);
    String str(Object? v) => v is String ? v : '';
    final sk = str(raw['sk']);
    return LastfmState(
      sk: sk.isEmpty ? null : sk,
      apiKey: str(raw['apiKey']),
      apiSecret: str(raw['apiSecret']),
      scrobbleEnabled: raw['scrobble'] == true,
      nowPlayingEnabled: raw['nowPlaying'] == true,
      user: str(raw['user']),
    );
  }

  void _save() => ref.read(jsonStoreProvider).write(_key, {
    'sk': state.sk,
    'apiKey': state.apiKey,
    'apiSecret': state.apiSecret,
    'scrobble': state.scrobbleEnabled,
    'nowPlaying': state.nowPlayingEnabled,
    'user': state.user,
  });

  /// Сохранить ключи приложения. Пустые не сохраняем — на ПК это тост
  /// «введи оба ключа».
  bool saveKeys(String apiKey, String apiSecret) {
    final k = apiKey.trim();
    final s = apiSecret.trim();
    if (k.isEmpty || s.isEmpty) {
      state = state.copyWith(note: const LfmNote(LfmNoteKind.needKeys));
      return false;
    }
    state = state.copyWith(apiKey: k, apiSecret: s, clearNote: true);
    _save();
    return true;
  }

  /// Шаг 1: разовый токен и переход в браузер.
  Future<void> startOAuth() async {
    if (!state.hasKeys) {
      state = state.copyWith(note: const LfmNote(LfmNoteKind.needKeys));
      return;
    }
    _pendingToken = null;
    state = state.copyWith(
      busy: true,
      oauthPending: false,
      note: const LfmNote(LfmNoteKind.gettingToken),
    );
    final r = await lastfmGetToken(state.apiKey);
    final token = r.token;
    if (token == null) {
      state = state.copyWith(
        busy: false,
        note: r.message == null
            ? const LfmNote(LfmNoteKind.networkError)
            : LfmNote(LfmNoteKind.error, r.message),
      );
      return;
    }
    _pendingToken = token;
    state = state.copyWith(
      busy: false,
      oauthPending: true,
      note: const LfmNote(LfmNoteKind.confirmAccess),
    );
    // Страница подтверждения открывается в браузере: пароль в приложение не
    // вводится, в этом весь смысл входа через Last.fm.
    unawaited(openLastfmPage(lastfmAuthUrl(state.apiKey, token)));
  }

  /// Шаг 2: обмен подтверждённого токена на ключ сессии.
  ///
  /// [silent] — проверка «на всякий случай» при возвращении в приложение из
  /// браузера: она не должна ни ругаться на неподтверждённый доступ, ни
  /// подменять уже показанную подсказку.
  Future<bool> finishOAuth({bool silent = false}) async {
    final token = _pendingToken;
    if (token == null) {
      if (!silent) {
        state = state.copyWith(note: const LfmNote(LfmNoteKind.loginFirst));
      }
      return false;
    }
    if (state.busy) return false;
    // Тихая проверка подсказку не трогает вовсе: на экране висит
    // «подтверди доступ», и подменять её на «проверяю» ради фоновой попытки
    // незачем.
    state = silent
        ? state.copyWith(busy: true)
        : state.copyWith(busy: true, note: const LfmNote(LfmNoteKind.checking));
    final r = await lastfmGetSession(
      apiKey: state.apiKey,
      apiSecret: state.apiSecret,
      token: token,
    );
    final session = r.session;
    if (session == null) {
      // «Не подтверждено» — нормальный ответ на тихую проверку: человек ушёл в
      // браузер и вернулся, ничего там не нажав. Ругаемся только по кнопке.
      state = silent
          ? state.copyWith(busy: false)
          : state.copyWith(
              busy: false,
              note: r.message == null
                  ? const LfmNote(LfmNoteKind.notConfirmed)
                  : LfmNote(LfmNoteKind.error, r.message),
            );
      return false;
    }
    _pendingToken = null;
    // Вошли — оба тумблера включаются сами, как на ПК: подключать Last.fm и не
    // скробблить незачем.
    state = state.copyWith(
      sk: session.key,
      user: session.name,
      scrobbleEnabled: true,
      nowPlayingEnabled: true,
      oauthPending: false,
      busy: false,
      clearNote: true,
    );
    _save();
    return true;
  }

  void logout() {
    _pendingToken = null;
    _nowTrack = null;
    state = state.copyWith(
      clearSk: true,
      user: '',
      oauthPending: false,
      busy: false,
      clearNote: true,
    );
    _save();
  }

  void setScrobble(bool on) {
    state = state.copyWith(scrobbleEnabled: on);
    _save();
  }

  void setNowPlaying(bool on) {
    state = state.copyWith(nowPlayingEnabled: on);
    _save();
  }

  /// Убрать подсказку — например при уходе с экрана.
  void clearNote() {
    if (state.note == null) return;
    state = state.copyWith(clearNote: true);
  }

  // ── Скробблинг ────────────────────────────────────────────────────────────

  /// Новый трек заиграл: запоминаем его и обновляем «сейчас играет».
  void onTrackStart(Track track) {
    _nowTrack = (
      artist: track.artist,
      track: track.name,
      album: track.album ?? '',
    );
    _startedAt = ref.read(lfmClockProvider)().millisecondsSinceEpoch ~/ 1000;
    _scrobbled = false;
    final sk = state.sk;
    if (sk == null || !state.nowPlayingEnabled) return;
    unawaited(
      lastfmNowPlaying(
        apiKey: state.apiKey,
        apiSecret: state.apiSecret,
        sk: sk,
        artist: _nowTrack!.artist,
        track: _nowTrack!.track,
        album: _nowTrack!.album,
      ),
    );
  }

  /// Тик позиции: дошли до порога — засчитываем. Один трек засчитывается один
  /// раз, до следующего [onTrackStart].
  void onProgress(Duration position, Duration? duration) {
    final now = _nowTrack;
    if (_scrobbled || now == null) return;
    if (duration == null || duration <= Duration.zero) return;
    if (position < kLfmMinListen) return;
    if (position < kLfmAbsolute &&
        position.inMilliseconds < duration.inMilliseconds / 2) {
      return;
    }
    _scrobbled = true;
    final sk = state.sk;
    if (sk == null || !state.scrobbleEnabled) return;
    unawaited(
      lastfmScrobble(
        apiKey: state.apiKey,
        apiSecret: state.apiSecret,
        sk: sk,
        artist: now.artist,
        track: now.track,
        album: now.album,
        timestamp: _startedAt,
      ),
    );
  }
}

/// Открыть страницу Last.fm в браузере. Отдельной переменной — тесты подменяют
/// её, чтобы не поднимать браузер.
Future<bool> Function(String url) openLastfmPage = defaultOpenLastfmPage;

Future<bool> defaultOpenLastfmPage(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
